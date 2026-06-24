import os
import sys
import json
import time
import logging
import subprocess
import importlib
from typing import Any

# =========================================================================
# SDK MONKEYPATCH: Fix Pydantic AgentCard Serialization in vertexai SDK
# =========================================================================
from google.protobuf import json_format
from pydantic import BaseModel

original_message_to_json = json_format.MessageToJson

def patched_message_to_json(message, *args, **kwargs):
    if isinstance(message, BaseModel):
        return message.model_dump_json(exclude_none=True)
    elif isinstance(message, dict):
        return json.dumps(message)
    try:
        return original_message_to_json(message, *args, **kwargs)
    except AttributeError:
        return json.dumps(message)

json_format.MessageToJson = patched_message_to_json
# =========================================================================

import vertexai
from vertexai._genai import _agent_engines_utils
from vertexai._genai.types import AgentEngineConfig

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("deploy")

def generate_class_methods_from_agent(agent_instance: Any) -> list[dict[str, Any]]:
    """Generate method specifications with schemas from agent's register_operations()."""
    registered_operations = _agent_engines_utils._get_registered_operations(
        agent=agent_instance
    )
    class_methods_spec = _agent_engines_utils._generate_class_methods_spec_or_raise(
        agent=agent_instance,
        operations=registered_operations,
    )
    class_methods_list = [
        _agent_engines_utils._to_dict(method_spec) for method_spec in class_methods_spec
    ]
    return class_methods_list

def main():
    PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT")
    if not PROJECT_ID:
        print("❌ ERROR: GOOGLE_CLOUD_PROJECT environment variable is not set. Run this in Cloud Shell or set the variable.")
        sys.exit(1)

    LOCATION = os.environ.get("GOOGLE_CLOUD_REGION", "us-central1")
    REQUIREMENTS_FILE = "agent/requirements.txt"
    AGENT_NAME = "price-match-agent"
    DISPLAY_NAME = "Price Match Agent"
    MODULE_PATH = "agent.price_match_agent"
    OBJECT_NAME = "agent_engine"

    print("============================================================")
    print("🚀 DEPLOYING PRICE MATCH AGENT TO VERTEX AI RUNTIME 🚀")
    print("============================================================")
    print(f"👉 Target Project: {PROJECT_ID}")
    print(f"👉 Target Location: {LOCATION}")
    print(f"👉 Requirements File: {REQUIREMENTS_FILE}")
    print("────────────────────────────────────────────────────────────")

    # 1. Initialize the Vertex AI client
    vertexai.init(project=PROJECT_ID, location=LOCATION)
    
    from vertexai._genai.client import Client
    client = Client(project=PROJECT_ID, location=LOCATION)

    sys.path.insert(0, os.getcwd())

    env_vars = {
        "GOOGLE_CLOUD_REGION": LOCATION,
        "GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY": "true",
        "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT": "true",
        "OTEL_TRACES_SAMPLER": "always_on",
    }

    # 2. Import the agent instance to generate class methods schemas
    print(f"🔍 Inspecting entrypoint: {MODULE_PATH}.{OBJECT_NAME}...")
    try:
        module = importlib.import_module(MODULE_PATH)
        agent_instance = getattr(module, OBJECT_NAME)
    except Exception as e:
        print(f"  ❌ Failed to import agent entrypoint: {e}")
        sys.exit(1)
        
    class_methods_list = generate_class_methods_from_agent(agent_instance)
    class_methods_list.append({
        "name": "async_stream_query",
        "api_mode": "async_stream"
    })
    class_methods_list.append({
        "name": "query",
        "api_mode": ""
    })
    
    # 3. Clean up stale engines with matching names to prevent duplicates
    print(f"🧹 Scanning for stale engines matching '{AGENT_NAME}'...")
    try:
        for eng in client.agent_engines.list():
            res = eng.api_resource
            if res.display_name in [AGENT_NAME, DISPLAY_NAME] or res.name.split("/")[-1] == AGENT_NAME:
                print(f"   🗑️ Found stale engine: {res.name} (Display: '{res.display_name}'). Deleting...")
                try:
                    client.agent_engines.delete(name=res.name, force=True)
                    print("     Deleted successfully!")
                except Exception as del_err:
                    print(f"     ⚠️ Delete failed: {del_err}")
    except Exception as list_err:
        print(f"   ⚠️ Could not scan existing engines: {list_err}")

    # 4. Build configuration block
    config = AgentEngineConfig(
        display_name=DISPLAY_NAME,
        description="Front-line Price Match Verification Agent. Calculates discounts and approves <= 20% directly.",
        source_packages=["./agent"],
        entrypoint_module=MODULE_PATH,
        entrypoint_object=OBJECT_NAME,
        class_methods=class_methods_list,
        env_vars=env_vars,
        requirements_file=REQUIREMENTS_FILE,
        min_instances=1,
        max_instances=3,
        agent_framework="google-adk",
        identity_type="AGENT_IDENTITY",
    )
    
    print(f"🚀 Deploying Reasoning Engine instance to Vertex AI...")
    try:
        remote_agent = client.agent_engines.create(config=config)
        engine_urn = remote_agent.api_resource.name
        engine_id = engine_urn.split("/")[-1]
        effective_identity = getattr(remote_agent.api_resource.spec, "effective_identity", None)
        system_sa = getattr(remote_agent.api_resource, "service_account", None)
        print(f"  ✅ Deployed successfully! URN: {engine_urn}")
        print(f"     🛡️ Provisioned Agent Identity (System SA): {system_sa}")
        print(f"     🔗 Workload Identity Principal: {effective_identity}")
    except Exception as e:
        print(f"  ❌ Failed to deploy agent: {e}")
        sys.exit(1)

    # 5. Automatically grant required IAM roles to the Agent Identity workload principal
    print(f"🔒 Granting required IAM permissions to Agent Identity workload principal...")
    
    import google.auth
    from google.auth.transport.requests import Request
    try:
        creds, _ = google.auth.default()
        auth_request = Request()
        creds.refresh(auth_request)
        access_token = creds.token
    except Exception as token_err:
        print(f"  ⚠️ Could not fetch credentials token for gcloud subprocesses: {token_err}")
        access_token = None
        
    env = os.environ.copy()
    if access_token:
        env["CLOUDSDK_AUTH_ACCESS_TOKEN"] = access_token

    # Query project number for the workload identity principal
    try:
        proj_info = subprocess.run(
            ["gcloud", "projects", "describe", PROJECT_ID, "--format=value(projectNumber)"],
            capture_output=True, text=True, check=True, env=env
        )
        project_number = proj_info.stdout.strip()
        print(f"  ℹ️ Numerical project number resolved: {project_number}")
    except Exception as proj_err:
        print(f"  ⚠️ Could not resolve project number: {proj_err}. Falling back to name.")
        project_number = PROJECT_ID

    roles = [
        "roles/aiplatform.user",
        "roles/agentregistry.viewer",
        "roles/mcp.toolUser",
        "roles/cloudtrace.agent",
        "roles/bigquery.admin",
        "roles/telemetry.writer"
    ]
    if "@" in str(effective_identity):
        member_string = f"serviceAccount:{effective_identity}"
    else:
        member_string = f"principal://{effective_identity}"

    for role in roles:
        print(f"   ➕ Binding role {role} to {member_string}...")
        for attempt in range(5):
            res = subprocess.run([
                "gcloud", "projects", "add-iam-policy-binding", PROJECT_ID,
                f"--member={member_string}",
                f"--role={role}"
            ], env=env, capture_output=True, text=True)
            if res.returncode == 0:
                break
            if "concurrent policy changes" in res.stderr or "conflict" in res.stderr.lower():
                print(f"      ⚠️ IAM policy write collision. Retrying in {2 ** attempt} seconds...")
                time.sleep(2 ** attempt)
            else:
                print(f"  ❌ Failed to bind role {role}: {res.stderr}")
                sys.exit(1)
        else:
            print(f"  ❌ Max retries reached for role {role}")
            sys.exit(1)
    print("  ✅ All permissions granted successfully!")

    print("\n============================================================")
    print("🎉 SUCCESS! Price Match Agent Deployed & Secured!")
    print("============================================================")
    print(f"👉 Agent Engine ID: {engine_id}")
    print(f"👉 Agent URN: {engine_urn}")
    print("────────────────────────────────────────────────────────────")
    print("💡 To test the agent runtime, execute the following command:")
    print("────────────────────────────────────────────────────────────")
    print(f"curl -X POST \\")
    print(f"  -H \"Authorization: Bearer $(gcloud auth print-access-token)\" \\")
    print(f"  -H \"Content-Type: application/json\" \\")
    print(f"  -d '{{\"input\": \"verify competitor price match for Barista Pro Espresso Machine SKU-HSE-4455 original price 450 requested price 400\"}}' \\")
    print(f"  \"https://{LOCATION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}/reasoningEngines/{engine_id}:streamQuery?alt=sse\"")
    print("============================================================")

if __name__ == "__main__":
    main()

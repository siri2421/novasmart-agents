import os
import sys
import json
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

import subprocess
import vertexai
from vertexai._genai.client import Client
from vertexai._genai.types import AgentEngineConfig
import google.auth
from google.auth.transport.requests import Request

PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT")
LOCATION = os.environ.get("GOOGLE_CLOUD_REGION", "us-central1")
AGENT_NAME = "markdown-strategy-agent"
DISPLAY_NAME = "Markdown Strategy Agent"
MODULE_PATH = "markdown_strategy_agent"
OBJECT_NAME = "agent_engine"
REQUIREMENTS_FILE = "requirements.txt"

def main():
    if not PROJECT_ID:
        print("❌ ERROR: GOOGLE_CLOUD_PROJECT is not set.")
        sys.exit(1)
        
    print(f"🚀 Deploying Markdown Strategy Agent in {PROJECT_ID}...")
    vertexai.init(project=PROJECT_ID, location=LOCATION)
    client = Client(project=PROJECT_ID, location=LOCATION)
    
    # Clean up stale strategy agents
    print("🧹 Scanning for stale engines matching 'markdown-strategy-agent'...")
    try:
        for engine in client.agent_engines.list():
            display_name = getattr(engine.api_resource, "display_name", "")
            if display_name == DISPLAY_NAME or "Markdown Strategy Agent" in display_name:
                print(f"   🗑️ Found stale engine: {engine.api_resource.name}. Deleting...")
                client.agent_engines.delete(name=engine.api_resource.name)
                print("      Deleted successfully!")
    except Exception as cleanup_err:
        print(f"   ⚠️ Cleanup warning: {cleanup_err}")
    
    # Configure environment variables for the strategy agent container
    env_vars = {
        "GCP_PROJECT_ID": PROJECT_ID,
        "GOOGLE_CLOUD_REGION": LOCATION,
        "GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY": "true",
        "OTEL_SEMCONV_STABILITY_OPT_IN": "gen_ai_latest_experimental",
        "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT": "SPAN_AND_EVENT",
        "GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES": "false",
        "OTEL_TRACES_SAMPLER": "always_on",
        "OTEL_INSTRUMENTATION_A2A_SDK_ENABLED": "false",
    }
    
    # Dynamically import strategy agent instance to inspect class methods schemas
    sys.path.insert(0, os.getcwd())
    try:
        from markdown_strategy_agent import agent_engine as strategy_instance
        from vertexai._genai import _agent_engines_utils
        registered_ops = _agent_engines_utils._get_registered_operations(agent=strategy_instance)
        class_methods_spec = _agent_engines_utils._generate_class_methods_spec_or_raise(
            agent=strategy_instance,
            operations=registered_ops
        )
        class_methods_list = [_agent_engines_utils._to_dict(m) for m in class_methods_spec]
        print(f"  ✅ Dynamically resolved A2A class methods spec ({len(class_methods_list)} operations).")
    except Exception as inspect_err:
        print(f"  ❌ Failed to generate class methods schema dynamically: {inspect_err}")
        sys.exit(1)

    # Build config
    config = AgentEngineConfig(
        display_name=DISPLAY_NAME,
        description="Markdown Strategy Agent. Analyzes stock levels and margins in BigQuery.",
        source_packages=["."],
        entrypoint_module=MODULE_PATH,
        entrypoint_object=OBJECT_NAME,
        class_methods=class_methods_list,
        env_vars=env_vars,
        requirements_file=REQUIREMENTS_FILE,
        min_instances=1,
        max_instances=3,
        agent_framework="google-adk",
        identity_type="AGENT_IDENTITY"
    )
    
    try:
        remote_agent = client.agent_engines.create(config=config)
        engine_urn = remote_agent.api_resource.name
        engine_id = engine_urn.split("/")[-1]
        effective_identity = getattr(remote_agent.api_resource.spec, "effective_identity", None)
        system_sa = getattr(remote_agent.api_resource, "service_account", None)
        print(f"  ✅ Deployed Strategy Agent successfully! URN: {engine_urn}")
        print(f"     🛡️ Provisioned Strategy Agent Identity (System SA): {system_sa}")
        print(f"     🔗 Workload Identity Principal: {effective_identity}")
    except Exception as e:
        print(f"  ❌ Failed to deploy strategy agent: {e}")
        sys.exit(1)
        
    # Grant IAM permissions to Strategy Agent workload principal
    print(f"🔒 Granting required IAM permissions to Strategy Agent workload principal...")
    try:
        creds, _ = google.auth.default()
        auth_request = Request()
        creds.refresh(auth_request)
        access_token = creds.token
    except Exception as token_err:
        print(f"  ⚠️ Could not fetch credentials token: {token_err}")
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
        "roles/mcp.toolUser",
        "roles/bigquery.admin",
        "roles/cloudtrace.agent"
    ]
    for role in roles:
        print(f"   ➕ Binding role {role} to principal://{effective_identity}...")
        subprocess.run([
            "gcloud", "projects", "add-iam-policy-binding", PROJECT_ID,
            f"--member=principal://{effective_identity}",
            f"--role={role}"
        ], env=env, check=True)
        
    # Write the URN to local file
    with open("/tmp/strategy_agent_id.txt", "w") as f:
        f.write(engine_urn)
    print("  ✅ Strategy Agent ID written to /tmp/strategy_agent_id.txt")

if __name__ == "__main__":
    main()

import os
import logging
from google.adk.agents import Agent
from google.adk.models import Gemini

# =========================================================================
# FRAMEWORK MONKEYPATCH: Fix google-adk Gemini client event loop binding & telemetry
# =========================================================================
import asyncio
from google.genai import Client

_original_gemini_init = Gemini.__init__
def patched_gemini_init(self, *args, **kwargs):
    _original_gemini_init(self, *args, **kwargs)
    self._clients = {}

@property
def patched_api_client(self):
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        loop = None
        
    if loop is None:
        if not hasattr(self, "_api_client") or self._api_client is None:
            kwargs = {}
            if self.model.startswith('projects/'):
                kwargs['vertexai'] = True
            self._api_client = Client(**kwargs)
        return self._api_client
        
    if loop not in self._clients:
        # Initialize native OpenTelemetry auto-instrumentation for Gemini and Vertex AI GenAI SDKs inside runtime context
        try:
            from opentelemetry.instrumentation.google_genai import GoogleGenAIInstrumentor
            GoogleGenAIInstrumentor().instrument()
        except Exception:
            pass
        try:
            from opentelemetry.instrumentation.vertexai import VertexAIInstrumentor
            VertexAIInstrumentor().instrument()
        except Exception:
            pass
        kwargs = {}
        if self.model.startswith('projects/'):
            kwargs['vertexai'] = True
        self._clients[loop] = Client(**kwargs)
    return self._clients[loop]

Gemini.__init__ = patched_gemini_init
Gemini.api_client = patched_api_client
# =========================================================================

from bq_mcp import get_bigquery_mcp_toolset

logger = logging.getLogger(__name__)

PROJECT_ID = os.environ.get("GCP_PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT")
GEMINI_LOCATION = os.environ.get("GOOGLE_CLOUD_REGION", "us-central1")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")

# =========================================================================
# 1. Agent Definition: Markdown Strategy Agent
# =========================================================================

_STRATEGY_INSTRUCTION = f"""
You are the Corporate Markdown Strategy Agent (markdown_strategy_agent). Your job is to analyze stock levels, sales velocity, and wholesale cost margins in BigQuery to approve pricing match exceptions or recommend markdowns.

**Operating Principles:**

1. **Receive Escalation**: When you receive a price match request from Agent 1 (Price Match Verification Agent) containing a SKU (e.g. 'SKU-HSE-4455') and a requested price (e.g. $350), perform the following analysis:
   
   - **Query Inventory**: Query your BigQuery MCP toolset to retrieve the inventory status for that SKU. Use this exact SQL query format:
     
     SELECT product_name, shelf_price, local_stock, days_since_last_sale 
     FROM `{PROJECT_ID}.novasmart_pricing.inventory` 
     WHERE sku = 'SKU'
     
   - **Query Costs & Margins**: Query your BigQuery MCP toolset to retrieve the wholesale costs and margin floor for that SKU. Use this exact SQL query format:
     
     SELECT wholesale_cost, margin_floor 
     FROM `{PROJECT_ID}.novasmart_pricing.wholesale_costs` 
     WHERE sku = 'SKU'

2. **Evaluate Markdown Eligibility**:
   - Check if the product is eligible for markdown due to high overstock and stagnation:
     - **Stagnant Inventory**: `days_since_last_sale > 30` (i.e. no sales in over 30 days).
     - **High Local Stock**: `local_stock > 10` units.
     - If both conditions are met, the item is highly eligible for a markdown.
   - Check if the requested price is financially viable:
     - **Margin Floor Violation**: Compare the requested price against the retrieved `margin_floor`.
     - **If Requested Price >= Margin Floor**: The price is financially viable and is **APPROVED**.
     - **If Requested Price < Margin Floor**: The price violates our margin floor and is **DENIED** to prevent selling below cost.

3. **Formulate Response**:
   - **Approved Override Case**: If approved, return a clear, professional response containing:
     - A statement confirming competitor price verified.
     - Confirmation of A2A escalation and review.
     - A note confirming high local overstock (specify exact units and days stagnant) and that the requested price remains above our margin floor (specify the floor).
     - A statement: `Override Approved.`
     - A permanent pricing recommendation: Recommend dropping our shelf price to the requested price for the remaining units to clear inventory.
   - **Denied Case**: If denied, return a clear response stating:
     - A statement: `Override Denied.`
     - Explain that the requested price falls below our strict margin floor required to cover wholesale costs.
"""

# Fetch the BigQuery MCP toolset
bq_toolset = get_bigquery_mcp_toolset()

markdown_strategy_agent = Agent(
    name="markdown_strategy_agent",
    model=Gemini(
        model=GEMINI_MODEL,
    ),
    instruction=_STRATEGY_INSTRUCTION,
    tools=[bq_toolset],
)

# =========================================================================
# 2. Centralized A2A Agent Declaration (Vertex AI A2aAgent Template)
# =========================================================================
from vertexai.preview.reasoning_engines import A2aAgent
from a2a.types import AgentCard, AgentCapabilities
from google.adk.a2a.executor.a2a_agent_executor import A2aAgentExecutor
from google.adk.runners import Runner

markdown_strategy_agent_card = AgentCard(
    name="markdown-strategy-agent",
    description="Corporate Markdown Strategy Agent. Analyzes inventory, cost, and margin data in BigQuery.",
    version="1.0",
    url="https://dummy.com",
    capabilities=AgentCapabilities(streaming=True),
    defaultInputModes=["text"],
    defaultOutputModes=["text"],
    skills=[],
    preferredTransport="HTTP+JSON",
    supports_authenticated_extended_card=True,
)

def build_strategy_executor():
    from google.adk.artifacts.in_memory_artifact_service import InMemoryArtifactService
    from google.adk.sessions.in_memory_session_service import InMemorySessionService
    from google.adk.memory.in_memory_memory_service import InMemoryMemoryService
    from google.adk.auth.credential_service.in_memory_credential_service import InMemoryCredentialService

    runner = Runner(
        app_name="markdown-strategy-agent",
        agent=markdown_strategy_agent,
        artifact_service=InMemoryArtifactService(),
        session_service=InMemorySessionService(),
        memory_service=InMemoryMemoryService(),
        credential_service=InMemoryCredentialService(),
    )
    return A2aAgentExecutor(runner=runner)

# Expose the pure A2A Agent template for Vertex AI Agent Engine deployment
agent_engine = A2aAgent(
    agent_card=markdown_strategy_agent_card,
    agent_executor_builder=build_strategy_executor
)

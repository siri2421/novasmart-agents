const express = require('express');
const path = require('path');
const fs = require('fs');
const { GoogleAuth } = require('google-auth-library');
const crypto = require('crypto');
require('dotenv').config();

const app = express();
app.use(express.json());

// Expose static frontend assets (HTML, CSS, JS) from the public/ directory
app.use(express.static(path.join(__dirname, 'public')));

// Initialize the Google Auth Client using Application Default Credentials (ADC)
const auth = new GoogleAuth({
  scopes: 'https://www.googleapis.com/auth/cloud-platform'
});

// Load the 50 premium items catalog
const productsFilePath = path.join(__dirname, 'products.json');
let productsCatalog = [];
try {
  productsCatalog = JSON.parse(fs.readFileSync(productsFilePath, 'utf8'));
} catch (err) {
  console.error('❌ Failed to read products.json:', err);
}

// =========================================================================
// API ENDPOINT: Fetch Product Catalog
// =========================================================================
app.get('/api/products', (req, res) => {
  res.json(productsCatalog);
});

// =========================================================================
// API ENDPOINT: Proxy Chat to Live Vertex AI Reasoning Engine
// =========================================================================
app.post('/api/chat', async (req, res) => {
  const { prompt, sessionId } = req.body;

  if (!prompt) {
    return res.status(400).json({ error: 'Prompt is required' });
  }

  // 1. Resolve environment parameters and cloud trace context
  let projectId = process.env.GCP_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) {
    try {
      projectId = await auth.getProjectId();
    } catch (err) {
      console.error('⚠️ Failed to auto-resolve project ID from ADC:', err);
    }
  }
  const location = process.env.GCP_LOCATION || 'us-central1';
  const agentEngineId = process.env.AGENT_ENGINE_ID; // Pre-deployed Agent 1 ID

  const cloudTraceHeader = req.headers['x-cloud-trace-context'];
  const traceparentHeader = req.headers['traceparent'];
  let traceId = null;
  if (cloudTraceHeader) {
    traceId = cloudTraceHeader.split('/')[0];
  } else if (traceparentHeader) {
    const parts = traceparentHeader.split('-');
    if (parts.length > 2) {
      traceId = parts[1];
    }
  }

  let outboundHeaders = {};

  if (!projectId || !agentEngineId) {
    console.error('❌ Environment configuration missing in server.js:', { projectId, agentEngineId });
    return res.status(500).json({
      error: 'Backend Configuration Error: GCP_PROJECT_ID and AGENT_ENGINE_ID must be set on the server.'
    });
  }

  // 2. Fetch standard Google Access Token from ADC directly
  let authHeaders;
  try {
    const baseClient = await auth.getClient();
    authHeaders = await baseClient.getRequestHeaders();
  } catch (authErr) {
    console.error('❌ Failed to obtain Google credentials:', authErr);
    return res.status(500).json({
      error: `Authentication Error: Failed to obtain credentials: ${authErr.message}`
    });
  }

  // 3. Construct the standard streamQuery Endpoint URL (routed through Ingress Gateway if bound)
  let resolvedProjectId = projectId;
  let resolvedLocation = location;
  let resolvedAgentEngineId = agentEngineId;

  if (agentEngineId && agentEngineId.startsWith('projects/')) {
    const parts = agentEngineId.split('/');
    if (parts.length >= 6) {
      resolvedProjectId = parts[1];
      resolvedLocation = parts[3];
      resolvedAgentEngineId = parts[5];
    }
  }

  const queryUrl = `https://${resolvedLocation}-aiplatform.googleapis.com/v1/projects/${resolvedProjectId}/locations/${resolvedLocation}/reasoningEngines/${resolvedAgentEngineId}:streamQuery?alt=sse`;

  const authenticatedUser = req.headers['x-goog-authenticated-user-email'] || req.headers['x-authenticated-user-email'];
  const resolvedUserId = authenticatedUser
    ? authenticatedUser.replace('accounts.google.com:', '').trim()
    : (process.env.USER_ID || 'novasmart-storeagent');

  // 4. Construct the payload targeting the console Playground execution handler (streaming_agent_run_with_events)
  const requestJson = {
    message: {
      parts: [
        { text: prompt }
      ]
    },
    user_id: resolvedUserId,
    session_id: sessionId || null
  };

  const requestBody = {
    classMethod: 'streaming_agent_run_with_events',
    input: {
      request_json: JSON.stringify(requestJson)
    }
  };

  console.log(`🤖 Opening persistent streamQuery SSE connection through Ingress Gateway...`);

  // 5. Execute the streaming REST API call to Vertex AI using native fetch
  try {
    const response = await fetch(queryUrl, {
      method: 'POST',
      headers: {
        ...authHeaders,
        ...outboundHeaders,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(requestBody)
    });

    // 6. Handle HTTP error codes
    if (!response.ok) {
      const responseText = await response.text();
      console.error('❌ Reasoning Engine returned raw error response:', response.status, responseText);

      let responseData;
      try {
        responseData = JSON.parse(responseText);
      } catch (err) {
        responseData = { error: { message: responseText || `HTTP ${response.status}: ${response.statusText}` } };
      }

      console.error('❌ Reasoning Engine returned HTTP error:', response.status, responseData);

      const errorMessage = responseData.error?.message || '';
      const isSafetyBlock = errorMessage.includes('Model Armor') || errorMessage.includes('content security');

      return res.status(isSafetyBlock ? 400 : response.status).json({
        error: isSafetyBlock
          ? { message: responseData.error.message }
          : (responseData.error || { message: responseData.error?.message || 'Reasoning Engine execution failed.' }),
        traceId: traceId || null,
        projectId: projectId
      });
    }

    // 7. Parse the SSE stream line-by-line
    let botResponseText = '';
    const decoder = new TextDecoder('utf-8');
    let remaining = '';

    const reader = response.body.getReader();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const decodedChunk = decoder.decode(value, { stream: true });
        const lines = (remaining + decodedChunk).split('\n');
        remaining = lines.pop(); // Save incomplete line for next chunk

        for (const line of lines) {
          const trimmedLine = line.trim();
          if (!trimmedLine) continue;

          console.log('📖 Server parsed line:', trimmedLine);

          let lineContent = trimmedLine;
        if (trimmedLine.startsWith('data:')) {
          lineContent = trimmedLine.slice(5).trim();
        }
        if (!lineContent) continue;

        try {
          const eventData = JSON.parse(lineContent);

          // Check for error in payload (e.g. { "code": 400, "message": "..." })
          if (eventData.code && eventData.code >= 400) {
            throw new Error(`Stream error: ${eventData.message || 'Unknown error'}`);
          }

          // Format 1: streaming_agent_run_with_events consolidated format
          if (eventData.events && Array.isArray(eventData.events)) {
            for (const singleEvent of eventData.events) {
              if (singleEvent.content && singleEvent.content.parts) {
                for (const part of singleEvent.content.parts) {
                  if (part.text) {
                    botResponseText += part.text;
                  }
                }
              }
            }
          }

          // Format 2: Standard ADK/ReasoningEngine streaming event format
          if (eventData.content && eventData.content.parts) {
            const parts = eventData.content.parts;
            for (const part of parts) {
              if (part.text) {
                botResponseText += part.text;
              }
            }
          }
        } catch (parseErr) {
          console.warn('⚠️ Failed to parse stream line:', lineContent, parseErr.message);
          // If it's a real error thrown by us above, propagate it
          if (parseErr.message && parseErr.message.startsWith('Stream error:')) {
            throw parseErr;
          }
        }
      }
    }
    } finally {
      reader.releaseLock();
    }

    console.log(`📥 Successfully aggregated streamQuery response: "${botResponseText.slice(0, 60)}..."`);
    res.json({ response: botResponseText || 'Stream completed but no response was found.' });

  } catch (fetchErr) {
    console.error('❌ Failed to stream from Vertex AI:', fetchErr);

    // Map Model Armor safety violations to 400 so the UI renders the glowing red safety bubble
    const isSafetyBlock = fetchErr.message && (
      fetchErr.message.includes('Model Armor') ||
      fetchErr.message.includes('content security') ||
      fetchErr.message.includes('blocked')
    );

    res.status(isSafetyBlock ? 400 : 500).json({
      error: isSafetyBlock
        ? `${fetchErr.message.replace('Stream error: ', '')}`
        : `Network Error: Failed to communicate with Vertex AI Agent: ${fetchErr.message}`,
      traceId: traceId || null,
      projectId: projectId
    });
  }
});

// =========================================================================
// Serve the main single-page application for any other routes
// =========================================================================
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Start the Express Web Server
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`============================================================`);
  console.log(`🚀 NovaSmart Store Portal running on port: ${PORT}`);
  console.log(`👉 Active Project: ${process.env.GCP_PROJECT_ID || 'Pending'}`);
  console.log(`👉 Live Agent 1: ${process.env.AGENT_ENGINE_ID || 'Pending'}`);
  console.log(`============================================================`);
});

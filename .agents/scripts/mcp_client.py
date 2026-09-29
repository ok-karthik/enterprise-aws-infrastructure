#!/usr/bin/env python3
"""
Lightweight MCP (Model Context Protocol) client for the IaC Generation Agent (PLAN 11.3).

Talks to the HashiCorp terraform-mcp-server over Streamable HTTP (.agents/mcp/docker-compose.yml) to read Terraform
Registry provider documentation. **Read-only use only**: it calls provider-doc tools of the `registry` toolset and nothing
that creates or changes anything.

What a real MCP session needs, and what the first version of this client skipped:
  1. `initialize` (JSON-RPC) with the protocol version and client info; the server answers and may return a
     `Mcp-Session-Id` header that every later request must send back,
  2. a `notifications/initialized` notification,
  3. `Accept: application/json, text/event-stream` on every POST (the server may answer as a JSON body or as a
     Server-Sent-Events stream),
  4. only then `tools/call`.

The tool names are the ones in HashiCorp's reference (https://developer.hashicorp.com/terraform/mcp-server/reference,
read 2026-09-28): `search_providers` and `get_provider_details`. **The argument names of those two tools
(PROVIDER_SEARCH_ARGS, DETAILS_ARG below) are from memory of the server, not from a run: nothing here was executed against
the real server** (it needs a Docker image pull). The client fails soft: any error returns None and the agent falls back to
its zero-dependency GitHub raw-docs scraper.

HashiCorp: "Do not use the MCP server with untrusted MCP clients or LLMs." Keep it on 127.0.0.1 (see the compose file).
"""

import json
import os
import re
from typing import Any, Optional
import urllib.error
import urllib.request

DEFAULT_MCP_URL = os.getenv("MCP_TERRAFORM_URL", "http://127.0.0.1:8080/mcp")
PROTOCOL_VERSION = "2025-03-26"
CLIENT_INFO = {"name": "enterprise-aws-infrastructure-iac-agent", "version": "1.0"}

# Unverified against a running server (see the module docstring).
PROVIDER_SEARCH_ARGS = {"provider_name": "aws", "provider_namespace": "hashicorp", "provider_document_type": "resources"}
DETAILS_ARG = "provider_doc_id"


class MCPClient:
    """Client for the HashiCorp terraform-mcp server (registry toolset, read-only)."""

    def __init__(self, endpoint_url: str = DEFAULT_MCP_URL, timeout: float = 3.0):
        self.endpoint_url = endpoint_url
        self.timeout = timeout
        self.session_id: Optional[str] = None
        self._initialized = False
        self._next_id = 0

    # -- transport ------------------------------------------------------------------
    def _post(self, message: dict) -> Optional[dict]:
        """POST one JSON-RPC message. Returns the response message (None for a notification or on any failure)."""
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        req = urllib.request.Request(self.endpoint_url, data=json.dumps(message).encode("utf-8"), headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                if resp.status not in (200, 201, 202):
                    return None
                session = resp.headers.get("Mcp-Session-Id")
                if session:
                    self.session_id = session
                body = resp.read().decode("utf-8")
                if "id" not in message or not body.strip():
                    return None  # a notification has no response
                return parse_response(body, resp.headers.get("Content-Type", ""), message["id"])
        except (urllib.error.URLError, TimeoutError, OSError, ValueError):
            return None

    def _request(self, method: str, params: dict) -> Optional[dict]:
        self._next_id += 1
        return self._post({"jsonrpc": "2.0", "id": self._next_id, "method": method, "params": params})

    def initialize(self) -> bool:
        """The MCP handshake. Safe to call twice."""
        if self._initialized:
            return True
        result = self._request("initialize", {"protocolVersion": PROTOCOL_VERSION, "capabilities": {}, "clientInfo": CLIENT_INFO})
        if not result or "result" not in result:
            return False
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        self._initialized = True
        return True

    # -- tools ----------------------------------------------------------------------
    def call_tool(self, tool_name: str, arguments: dict[str, Any]) -> Optional[str]:
        """Call one tool and return its text content, or None if the server is unavailable or the call failed."""
        if not self.initialize():
            return None
        response = self._request("tools/call", {"name": tool_name, "arguments": arguments})
        if not response:
            return None
        result = response.get("result") or {}
        if result.get("isError"):
            return None
        texts = [item.get("text", "") for item in result.get("content", []) if item.get("type") == "text"]
        return "\n\n".join(texts).strip() or None

    def get_provider_doc(self, resource_hint: str, provider: str = "hashicorp/aws") -> Optional[str]:
        """Provider documentation for a resource: `search_providers`, then `get_provider_details` on the best match."""
        if not resource_hint:
            return None
        namespace, _, name = provider.partition("/")
        args = {**PROVIDER_SEARCH_ARGS, "provider_namespace": namespace or "hashicorp", "provider_name": name or "aws", "service_slug": resource_hint}
        listing = self.call_tool("search_providers", args)
        if not listing:
            return None
        doc_id = first_doc_id(listing)
        if not doc_id:
            return listing  # the search result itself is still useful context
        return self.call_tool("get_provider_details", {DETAILS_ARG: doc_id}) or listing

    def is_available(self) -> bool:
        """Is the server reachable? Uses /health, which the server documents."""
        try:
            base = self.endpoint_url.rsplit("/", 1)[0]
            with urllib.request.urlopen(urllib.request.Request(base + "/health", method="GET"), timeout=1.0) as resp:
                return resp.status in (200, 204)
        except Exception:
            return False


def parse_response(body: str, content_type: str, request_id: int) -> Optional[dict]:
    """A response is either a plain JSON body or an SSE stream whose `data:` lines hold JSON-RPC messages."""
    if "text/event-stream" in content_type or body.lstrip().startswith(("event:", "data:", "id:")):
        for line in body.splitlines():
            if line.startswith("data:"):
                try:
                    message = json.loads(line[len("data:"):].strip())
                except ValueError:
                    continue
                if message.get("id") == request_id:
                    return message
        return None
    try:
        message = json.loads(body)
    except ValueError:
        return None
    return message if isinstance(message, dict) else None


def first_doc_id(listing: str) -> Optional[str]:
    """Pull the first provider document ID out of a search_providers result (a list of entries with a numeric ID)."""
    match = re.search(r"(?i)(?:provider[ _-]?doc[ _-]?id|id)\W{0,3}\s*[:=]?\s*[`\"']?(\d{3,})", listing)
    return match.group(1) if match else None

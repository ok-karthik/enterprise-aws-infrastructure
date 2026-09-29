# Terraform MCP server for the agents: notes for ADR 11 (PLAN 11.3)

**Status: evaluation notes, written by a model. Nothing here was run against the real server** (running it needs a Docker
image pull, which was avoided on a metered connection). The decision, "use it or not, and on what terms", belongs in
ADR 11 in the owner's words. These notes are the facts it can stand on.

## 1. What the agent connected to before (by reading the code, not by running it)

`.agents/scripts/mcp_client.py` posted `tools/call` to `MCP_TERRAFORM_URL` (default `http://localhost:8080/mcp`) with:

- **no `initialize` handshake and no session ID.** A Streamable-HTTP MCP server expects `initialize`, then
  `notifications/initialized`, then tool calls carrying the `Mcp-Session-Id` it handed out;
- **`Accept: application/json` only.** The server may answer with `text/event-stream`, and the spec asks clients to accept both;
- **tool names `get_provider_doc` and `search_registry`.** HashiCorp's reference lists `search_providers`,
  `get_provider_details`, `get_provider_capabilities`, `get_latest_provider_version`, `search_modules`, `get_module_details`,
  `get_latest_module_version`, `search_policies`, `get_policy_details`. The two names above are not among them.

So the most likely truth: **the agent has always used its GitHub raw-docs fallback**, and the "MCP" path never returned
anything. This is a reading of the code and the docs, not a measurement. To measure it: start the server
(`docker compose -f .agents/mcp/docker-compose.yml up -d`), then run
`python3 -c "from mcp_client import MCPClient; print(MCPClient().get_provider_doc('s3_bucket'))"` from `.agents/scripts/`
against the old and new client and see which returns text.

**Fixed now:** the client does the handshake, sends the session ID, accepts SSE and calls `search_providers` then
`get_provider_details`. It is tested against a fake local server (`.agents/tests/test_mcp_client.py`). **Still unverified:**
the *argument names* of those two tools (`provider_name`, `provider_namespace`, `service_slug`, `provider_document_type`,
`provider_doc_id`) are from memory. HashiCorp's reference gives only "service name" and "provider component ID". If the
real names differ, the client fails soft (returns nothing) and the agent falls back as before.

## 2. What it offers, read-only (HashiCorp README and reference, 2026-09-28)

- Latest release: `v1.3.0` (2026-08-26). The compose file pins `1.2.0`: upgrade on purpose.
- Toolsets: `registry`, `registry-private`, `terraform`, `all`, `default`; `--toolsets` or `--tools` limit them (not together).
  **The README and the reference page disagree on the default**, so set `--toolsets=registry` explicitly (open item in the compose file).
- `ENABLE_TF_OPERATIONS` is off by default; it gates the tools that create or change workspaces and runs.
- `TFE_TOKEN` is only for HCP Terraform / Terraform Enterprise features. Public registry docs do not need it.
- HTTP settings: `TRANSPORT_MODE=streamable-http`, `TRANSPORT_HOST` (default `127.0.0.1`; `0.0.0.0` inside Docker),
  `TRANSPORT_PORT` (8080), `MCP_ENDPOINT` (`/mcp`), `/health`, `MCP_CORS_MODE` (default `strict`).
- Security: "Do not use the MCP server with untrusted MCP clients or LLMs." Never pass tokens in query parameters. Use TLS if it is ever deployed centrally.

## 3. Proposed terms (what the compose file and client now match)

1. A pinned image tag, upgraded deliberately.
2. `--toolsets=registry` (open: needs the command line checked).
3. No `TFE_TOKEN`; `ENABLE_TF_OPERATIONS` unset.
4. Published on `127.0.0.1` only.
5. Trusted clients only: the IaC agent on a developer machine or in CI, never a shared or public endpoint.
6. The client calls read-only provider-doc tools only, and a test asserts that.

## 4. Terragrunt docs: default is "use neither"

No Terragrunt documentation server from Gruntwork was found that is free to use: their MCP server is hosted and needs a paid IaC Library
account. The community image `olofdevopsninja/terragrunt-mcp-server:latest` is a single-maintainer project on an unpinned tag, so it was
removed from the compose file.

## 5. For ADR 11, in your own words

- Is a docs server worth a running service, when the GitHub raw-docs fallback already works with no service at all?
- Does the answer change if the fallback breaks (GitHub rate limits, doc layout changes)?
- Who may run it, and on what network?
- What would make you turn on the private or terraform toolsets later, and who would approve it?

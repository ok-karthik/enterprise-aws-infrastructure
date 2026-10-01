# ADR 0011: Model Context Protocol (MCP) Server for Autonomous IaC Agents

- Status: draft
- Date: 2026-09-29

## Context

Autonomous AI coding agents (Claude Code, Antigravity IDE, pipeline healing bots) assist engineers in authoring, refactoring, and auditing Terraform and Terragrunt configurations. To operate effectively, agents require context regarding:
- Terraform provider schemas and documentation
- Registry module specifications
- Local module inputs, outputs, and dependencies

The Model Context Protocol (MCP) provides an open standard for LLMs to interface with external tools and resources. However, granting external or unconstrained MCP capabilities poses significant security and supply-chain risks.

## Decision

1. **Constrained, Read-Only MCP Integration**:
   - The platform integrates an isolated HashiCorp-compatible MCP server running locally on `127.0.0.1` (`.agents/mcp/docker-compose.yml` and `.agents/mcp/mcp_client.py`).
   - The MCP server is scoped exclusively to read-only schema queries, provider documentation lookups, and registry metadata inspection.
2. **Zero Execution Privileges**:
   - The MCP server has **no AWS credentials**, no access to S3 state files, and no capability to execute `terraform apply`, `destroy`, `import`, or `state rm`.
3. **Hard Local Agent Guardrails**:
   - Pre-command execution hooks (`.agents/hooks/guard.py`) strictly enforce safety invariants: blocking destructive commands, intercepting state-file manipulations, and requiring local offline verification (`verify-module`) after every module edit.

## What I chose against and what it cost

- **Full-Privilege MCP Server with Cloud Access**:
  - *Why rejected*: Allowing an agent to execute live cloud applies via an MCP tool introduces severe prompt injection and hallucination risks that could cause unreviewed production outages.
- **Unpinned Community MCP Containers**:
  - *Why rejected*: Unofficial Docker containers running with host network access represent a major supply chain attack vector.
- **Cost**:
  - Agents cannot automatically inspect live AWS resources directly via MCP; they must rely on planned diffs (`plan.json`) and local static analysis.

## Consequences

- Agents gain high-accuracy provider syntax and attribute documentation, reducing hallucinations during code generation.
- Security posture remains uncompromised: all mutations remain subject to Git pull requests, CODEOWNERS approval, and automated CI policy gates.

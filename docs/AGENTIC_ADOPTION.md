# Adopting agentic infrastructure workflows across an organisation

> **Model-written draft, not yet reviewed.** The owner rewrites this in their own words (PLAN 11.6) and can then give the
> two-minute version out loud. Until then, read it as a structured starting point, not as the owner's position.
> Section 5 mentions German and EU law: **it is not legal advice.** Have your legal team, data-protection officer and works
> council check it before you rely on it.

What "agentic workflows" means here: coding agents on developers' machines, an agent that turns requests and drift into pull
requests, and a healer that proposes fixes for red pipelines. All exist in this repository. None may apply infrastructure (see
[AGENT_AUTONOMY.md](AGENT_AUTONOMY.md)). This document is about taking the *way of working* from one repo to teams and then
to the whole organisation.

## 1. Why adoption fails

1. **Tool first, problem second.** A team is given an agent and no question to answer with it. Start from a task that hurts
   (a slow module review, a noisy drift queue) and check whether the agent helps.
2. **Trust is lost after one incident.** One agent-authored change that breaks something, or one leaked secret, and people stop
   using it for months. So guardrails come before enthusiasm.
3. **Security and legal are asked too late.** Data-processing terms, works-council agreement and the choice of LLM provider take
   weeks. Asking after the pilot means the pilot has to stop.
4. **Reviewers become the bottleneck.** Agents make more pull requests than people can read. If review time grows faster than the
   time saved, the whole thing is net negative. Watch time to first review.
5. **No owner.** Someone must own the guardrails, the metrics and the answer to "can I use it for X?".
6. **No numbers.** Without a baseline nobody can say whether it helped, and the first sceptic wins the argument.

## 2. Rollout in phases

| Phase | What | Exit test |
|---|---|---|
| **0. Guardrails** | Hooks and hard limits for local agents ([`.agents/AGENTS.md`](../.agents/AGENTS.md)), the autonomy table ([AGENT_AUTONOMY.md](AGENT_AUTONOMY.md)), `main` protected, CODEOWNERS on the checks. | The known gaps in the autonomy table are closed or accepted in writing. |
| **1. One pilot team, read-only use cases, 6-8 weeks** | Explain code, review a diff, draft a runbook, propose a module change as a pull request. No agent commits to a shared branch. | A baseline (lead time, review time, change failure rate) and at least 20 agent PRs, so the weekly summary means something. |
| **2. A paved road, run as a platform product** | A shared `AGENTS.md`, the hooks, a short list of approved MCP servers (see [`.agents/mcp/README.md`](../.agents/mcp/README.md)), golden-path templates (`.agents/catalog/`), a support channel. | A second team is productive without asking the pilot team. |
| **3. Champions and enablement** | One champion per team, a short onboarding session, an office hour, worked examples from real PRs. | Champions can answer "can I use it for X?" without escalating. |
| **4. Governance** | Review the metrics quarterly, decide level changes with an ADR, audit the agent action trail, keep the approved-tools list current. | The quarterly review has happened twice and changed something. |

Do the phases in order. A team that skips phase 0 is the one that produces the incident that ends the programme.

## 3. Roles

- **Agent owner** (one named person): owns the guardrails, the autonomy table and the metrics; decides a level change with an ADR.
- **Platform team:** builds and runs the paved road (templates, hooks, approved servers), supports the teams.
- **Security:** reviews the tool list, the data flow to LLM providers, secrets handling, and the audit trail. Signs off each level change.
- **Champions:** one per team; first line of help; feed problems back.
- **Works council and data-protection officer:** see section 5. They are consulted before the pilot, not after it.

## 4. Metrics per phase

The numbers come from the weekly summary (`delivery_metrics.py`, [SLO.md](SLO.md)), split into human and `ai-generated` PRs, reported
**per team, never per person**, with sample sizes.

| Phase | Watch | Why |
|---|---|---|
| 1 | Lead time, time to first review, change failure rate, reverts within 7 days, for agent PRs and human PRs side by side | Is the agent's work as good as a person's, and does it cost reviewers more time? |
| 2 | Adoption by team (number of teams with agent PRs), cost per verified change | Is it spreading, and what does it cost? |
| 3 | Share of agent PRs merged without changes, questions escalated | Are champions working? |
| 4 | Drift in the numbers over time, incidents involving an agent, exceptions granted | Is it still safe? |

Never publish a ranking of people. Do not use these numbers in performance reviews (see section 5).

## 5. Governance for Germany and the EU (check with legal, DPO and the works council)

These are the points to raise, not conclusions.

- **Works council co-determination.** In Germany, introducing a technical system that is *suited to* monitoring employees' behaviour or
  performance is subject to the works council's co-determination (Section 87(1) no. 6 of the Works Constitution Act, BetrVG). Delivery
  metrics split by team, and any log of what an agent or a person did, can qualify even if nobody intends to monitor. Involve the works council
  before the pilot, agree what is collected, at what level (team, not person), for how long, and who can see it.
- **GDPR and LLM providers.** Decide which code, logs and prompts may go to which provider. Points to settle with the DPO: a data-processing
  agreement with the provider, the processing region, retention and whether prompts are used for training, and whether infrastructure code or
  logs can contain personal data (usernames, emails in tags, IP addresses in logs). The repo's guardrails limit secrets; they do not remove
  personal data.
- **EU AI Act, AI literacy (Article 4).** Providers and deployers must take measures so that staff working with AI systems have a sufficient
  level of AI literacy. The enablement in phase 3 is where to document it.
- **Audit trail.** ISO 27001, NIS2 and DORA all expect you to be able to show who or what changed a production system and why. Agent actions
  need a trail: the pull request (author, label `ai-generated`, review), the commit, the workflow run, and the healer's log line when it stands down.
  Check what your retention and access rules require for logs that describe people's actions.

## 6. A 30-60-90 day plan

**Days 1-30: prepare.**
- Protect `main`, add CODEOWNERS for the checks, close or accept the gaps in [AGENT_AUTONOMY.md](AGENT_AUTONOMY.md).
- Name the agent owner. Talk to security, the DPO and the works council; agree what is collected and at what level.
- Pick the pilot team and three read-only use cases. Record the baseline numbers.

**Days 31-60: pilot.**
- Run the pilot team on the read-only use cases. Weekly summary, short retro every two weeks.
- Fix the paved road where the team gets stuck (templates, hooks, docs). Write down every incident, however small.
- Decision at day 60: continue, change, or stop, on the numbers and the retros.

**Days 61-90: widen, carefully.**
- A second team joins using only the paved road. Appoint champions. One onboarding session.
- First quarterly review: metrics, incidents, exceptions. Decide on levels with an ADR (none should move to L3 yet).
- Publish a one-page "what you may do with agents here" for everyone.

## What this draft does not know

It has no data from a real pilot. The phase lengths and exit tests are reasoned guesses. The legal points are a checklist of things to ask,
not answers. The owner replaces all of these with what actually happens.

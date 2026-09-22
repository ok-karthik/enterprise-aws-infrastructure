# Runbook: open SSH/RDP auto-remediation (PLAN 4.9)

`security/auto-remediation`'s Lambda removes any `0.0.0.0/0` / `::/0` ingress rule on port 22 or 3389 within seconds of it being created. This is one of the interview stories from the learning-plan (Sprint 2): "here is a real control, and here is the number that proves it works."

## How it works

See `iac-modules-repo/security/auto-remediation/README.md` for the full path (member account → forwarded EventBridge event → central bus in security-tooling → Lambda → assumes `security-remediation` back into the member account → revokes the rule → alerts). This runbook is only about **measuring** it.

## Measuring the time from open to closed

**Not measured yet.** This needs a real deployment; nothing here was run against AWS. Once the module is applied (owner step):

1. **Note the time.** In a **sandbox** account (never a real workload), authorize an open SSH rule:
   ```
   aws ec2 authorize-security-group-ingress --group-id <sg-id> --protocol tcp --port 22 --cidr 0.0.0.0/0
   ```
   Record the wall-clock time this command returns.
2. **Watch it get removed.** Poll (or watch CloudTrail/the security group in the console) until the rule is gone:
   ```
   watch -n1 'aws ec2 describe-security-groups --group-ids <sg-id> --query "SecurityGroups[0].IpPermissions"'
   ```
   Record the time it disappears.
3. **Check the alert.** The `security/security-alerts` topic's subscribed email should have the summary, including the Lambda's own measured `elapsed_seconds` (from `publish_summary` in `src/remediate_open_ssh.py`) — that number is more precise than the wall-clock one above, since it excludes CLI round-trip and polling latency.
4. **Record the result here:**

   | Date | Elapsed (Lambda's own measurement) | Elapsed (wall clock, step 1 to step 2) | Notes |
   |---|---|---|---|
   | _not run yet_ | | | |

   Target: under 30 seconds. If it is not, check first whether the delay is in event forwarding (member account → central bus) or in the Lambda's own assume-role/API calls (CloudWatch Logs, X-Ray tracing is on by default in the Lambda).

## What this does not cover yet

- The Config-rule trigger (PLAN 4.9's second trigger): not built, because PLAN 4.3 (the org Config recorder) is not done. Once it is, add a second EventBridge rule the same way and re-run this drill for that path too.
- Whether `AuthorizeSecurityGroupIngress` is the only event that can open a management port (`ModifySecurityGroupRules` can too, on some SDKs/console flows): check the current AWS CloudTrail event names before relying on coverage being complete, and add a second matching rule if there is a gap.

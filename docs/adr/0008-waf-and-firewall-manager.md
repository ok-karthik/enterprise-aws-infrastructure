# ADR 0008: AWS Firewall Manager vs WAF per Application Load Balancer

- Status: accepted
- Date: 2026-09-29

## Context

Protecting public-facing Application Load Balancers (ALBs) and CloudFront distributions against common web exploits (OWASP Top 10, SQL injection, cross-site scripting) requires AWS WAF. In an AWS Organizations environment, WAF policies can be applied either via AWS Firewall Manager centrally or configured directly per ALB via modular Terraform.

AWS Firewall Manager carries a high fixed price tag ($100 per policy per region per month), which must be evaluated against the operational benefits of centralized rule propagation.

## Decision

1. **Modular WAF per Application Load Balancer**: Implement reusable, hardened WAF web ACL configurations (`iac-modules-repo/edge/cloudfront` and ALB modules) containing AWS Managed Rule Groups (Core Rule Set, Known Bad Inputs, Amazon IP Reputation).
2. **Centralized WAF Logging**: Direct all WAF access logs across accounts to the compliance S3 bucket in `log-archive` via `iac-modules-repo/security/waf-logging`.
3. **AWS Firewall Manager as Opt-in for High Scale**: Maintain the `iac-modules-repo/security/firewall-manager` module as an optional, tested platform capability for when the organization exceeds 15+ public ALBs across accounts.

## What I chose against and what it cost

- **Mandatory AWS Firewall Manager from Day 1**:
  - *Why rejected*: AWS Firewall Manager costs $100/policy/region/month. Managing 2 policies (WAF for ALBs, WAF for CloudFront) across 2 regions costs $400/month in base licensing fees alone, even if only 2 public ALBs exist in the entire landing zone.
  - *Cost Comparison*: Individual WAF Web ACLs cost $5/month per ACL + $1/rule/month + $0.60 per million requests. For 2 ALBs, direct WAF costs ~$30/month vs $400/month for Firewall Manager.
  - *Trade-off*: Decentralized WAF modules require standardizing module usage in GitOps rather than relying on automatic cross-account enforcement from the management account.

## Consequences

- Massive cost avoidance during early and growth stages of platform scaleup.
- Identical security posture achieved via standardized Terraform modules and centralized logging.
- Clear migration threshold defined (when ALB count > 15, Firewall Manager becomes cost-neutral).

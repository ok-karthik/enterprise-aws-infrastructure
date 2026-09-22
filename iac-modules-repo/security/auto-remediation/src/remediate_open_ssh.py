"""Auto-remediation for open SSH/RDP security group rules (PLAN 4.9).

Triggered by an EventBridge rule on the CloudTrail-derived "AuthorizeSecurityGroupIngress" event, forwarded
from a member account to a central bus in security-tooling (see the Terraform side of this module; EventBridge
does not natively see another account's CloudTrail events). Assumes the narrow `security-remediation` role in
the member account (created by iac-modules-repo/governance/account-baseline), removes any 0.0.0.0/0 or ::/0
ingress rule on port 22 or 3389, tags the security group `remediated-by=auto`, and publishes a summary to the
security/security-alerts SNS topic.

The AWS-facing functions take a client as an argument (dependency injection) so the logic here is testable
with a hand-written fake client and no boto3 install needed (tests/test_remediate_open_ssh.py). `boto3` itself
is imported lazily, inside `handler()`, for the same reason: importing this module for its pure functions
must not require boto3 to be installed.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from typing import Any, Protocol

MANAGEMENT_PORTS: tuple[int, ...] = (22, 3389)


@dataclass(frozen=True)
class OpenRule:
    """One ingress rule that lets a management port in from the whole internet."""

    protocol: str
    from_port: int
    to_port: int
    cidr: str
    is_ipv6: bool


def find_open_management_port_rules(security_group: dict[str, Any]) -> list[OpenRule]:
    """Pure function: given a describe_security_groups()-shaped SG dict, return every ingress rule that
    opens SSH (22) or RDP (3389) to 0.0.0.0/0 or ::/0. No AWS calls, no side effects."""
    open_rules: list[OpenRule] = []
    for perm in security_group.get("IpPermissions", []):
        protocol = perm.get("IpProtocol", "-1")
        from_port = perm.get("FromPort", 0)
        to_port = perm.get("ToPort", 65535)
        if protocol not in ("tcp", "-1"):
            continue
        if not _overlaps_a_management_port(from_port, to_port):
            continue
        for ip_range in perm.get("IpRanges", []):
            if ip_range.get("CidrIp") == "0.0.0.0/0":
                open_rules.append(OpenRule(protocol, from_port, to_port, "0.0.0.0/0", False))
        for ip_range in perm.get("Ipv6Ranges", []):
            if ip_range.get("CidrIpv6") == "::/0":
                open_rules.append(OpenRule(protocol, from_port, to_port, "::/0", True))
    return open_rules


def _overlaps_a_management_port(from_port: int, to_port: int) -> bool:
    return any(from_port <= p <= to_port for p in MANAGEMENT_PORTS)


class Ec2Client(Protocol):
    def revoke_security_group_ingress(self, **kwargs: Any) -> dict[str, Any]: ...
    def create_tags(self, **kwargs: Any) -> dict[str, Any]: ...
    def describe_security_groups(self, **kwargs: Any) -> dict[str, Any]: ...


class StsClient(Protocol):
    def assume_role(self, **kwargs: Any) -> dict[str, Any]: ...


class SnsClient(Protocol):
    def publish(self, **kwargs: Any) -> dict[str, Any]: ...


def revoke_open_rules(ec2: Ec2Client, group_id: str, open_rules: list[OpenRule]) -> None:
    """Revoke every rule find_open_management_port_rules() found, then tag the group. No-op on an empty list."""
    ipv4_rules = [r for r in open_rules if not r.is_ipv6]
    ipv6_rules = [r for r in open_rules if r.is_ipv6]

    if ipv4_rules:
        ec2.revoke_security_group_ingress(
            GroupId=group_id,
            IpPermissions=[
                {
                    "IpProtocol": r.protocol,
                    "FromPort": r.from_port,
                    "ToPort": r.to_port,
                    "IpRanges": [{"CidrIp": r.cidr}],
                }
                for r in ipv4_rules
            ],
        )
    if ipv6_rules:
        ec2.revoke_security_group_ingress(
            GroupId=group_id,
            IpPermissions=[
                {
                    "IpProtocol": r.protocol,
                    "FromPort": r.from_port,
                    "ToPort": r.to_port,
                    "Ipv6Ranges": [{"CidrIpv6": r.cidr}],
                }
                for r in ipv6_rules
            ],
        )

    ec2.create_tags(Resources=[group_id], Tags=[{"Key": "remediated-by", "Value": "auto"}])


def extract_group_id_and_account(event: dict[str, Any]) -> tuple[str, str]:
    """Pure function: pull the security group id and the account id out of the forwarded CloudTrail-derived
    EventBridge event. Raises ValueError if the shape does not match."""
    detail = event.get("detail", {})
    request_params = detail.get("requestParameters", {})
    if "groupId" in request_params:
        account_id = event.get("account") or detail.get("recipientAccountId", "")
        return request_params["groupId"], account_id
    raise ValueError(f"Could not find a security group id in this event: {json.dumps(event)[:500]}")


def assume_remediation_role(sts: StsClient, account_id: str, role_name: str, partition: str = "aws") -> dict[str, str]:
    response = sts.assume_role(
        RoleArn=f"arn:{partition}:iam::{account_id}:role/{role_name}",
        RoleSessionName="auto-remediation",
    )
    creds = response["Credentials"]
    return {
        "aws_access_key_id": creds["AccessKeyId"],
        "aws_secret_access_key": creds["SecretAccessKey"],
        "aws_session_token": creds["SessionToken"],
    }


def publish_summary(
    sns: SnsClient,
    topic_arn: str,
    account_id: str,
    group_id: str,
    open_rules: list[OpenRule],
    elapsed_seconds: float,
) -> None:
    message = (
        f"Auto-remediation: removed {len(open_rules)} open rule(s) on {group_id} in account {account_id} "
        f"(0.0.0.0/0 or ::/0 on port 22/3389), {elapsed_seconds:.1f}s after the rule was created."
    )
    sns.publish(TopicArn=topic_arn, Message=message, Subject="Auto-remediation: open SSH/RDP rule removed")


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:  # pragma: no cover - thin AWS wiring
    """Lambda entry point. Not covered by unit tests directly (it does real boto3 calls); the logic it wires
    together is covered above. Verify this function itself with a real deployment (docs/runbooks/auto-remediation.md)."""
    import boto3  # local import: keeps this module importable in tests with no boto3 installed

    start = time.time()
    group_id, account_id = extract_group_id_and_account(event)

    role_name = os.environ["REMEDIATION_ROLE_NAME"]
    topic_arn = os.environ["ALERT_TOPIC_ARN"]
    partition = os.environ.get("AWS_PARTITION", "aws")

    sts = boto3.client("sts")
    creds = assume_remediation_role(sts, account_id, role_name, partition)
    ec2 = boto3.client("ec2", **creds)

    described = ec2.describe_security_groups(GroupIds=[group_id])
    security_group = described["SecurityGroups"][0]
    open_rules = find_open_management_port_rules(security_group)

    if open_rules:
        revoke_open_rules(ec2, group_id, open_rules)
        sns = boto3.client("sns")
        publish_summary(sns, topic_arn, account_id, group_id, open_rules, time.time() - start)

    return {"group_id": group_id, "account_id": account_id, "rules_removed": len(open_rules)}

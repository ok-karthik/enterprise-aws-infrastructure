"""Offline unit tests: `python3 -m unittest discover -s tests` from this module directory. No boto3, no
network: the AWS-facing functions in remediate_open_ssh.py take a client argument, so these tests pass in
hand-written fake clients instead of moto or a stubbed boto3 (either was acceptable per PLAN 4.9)."""

from __future__ import annotations

import unittest
from typing import Any

from src.remediate_open_ssh import (
    OpenRule,
    assume_remediation_role,
    extract_group_id_and_account,
    find_open_management_port_rules,
    publish_summary,
    revoke_open_rules,
)


def sg(ip_permissions: list[dict[str, Any]]) -> dict[str, Any]:
    return {"GroupId": "sg-open", "IpPermissions": ip_permissions}


class FindOpenManagementPortRulesTests(unittest.TestCase):
    def test_open_ssh_from_anywhere_is_found(self) -> None:
        group = sg([{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}])
        rules = find_open_management_port_rules(group)
        self.assertEqual(rules, [OpenRule("tcp", 22, 22, "0.0.0.0/0", False)])

    def test_open_rdp_from_anywhere_ipv6_is_found(self) -> None:
        group = sg([{"IpProtocol": "tcp", "FromPort": 3389, "ToPort": 3389, "Ipv6Ranges": [{"CidrIpv6": "::/0"}]}])
        rules = find_open_management_port_rules(group)
        self.assertEqual(rules, [OpenRule("tcp", 3389, 3389, "::/0", True)])

    def test_a_wide_port_range_that_includes_22_is_found(self) -> None:
        group = sg([{"IpProtocol": "tcp", "FromPort": 1, "ToPort": 65535, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}])
        rules = find_open_management_port_rules(group)
        self.assertEqual(len(rules), 1)

    def test_all_protocols_rule_that_includes_22_is_found(self) -> None:
        group = sg([{"IpProtocol": "-1", "FromPort": 0, "ToPort": 65535, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}])
        rules = find_open_management_port_rules(group)
        self.assertEqual(len(rules), 1)

    def test_ssh_scoped_to_a_real_cidr_is_not_flagged(self) -> None:
        group = sg([{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "10.0.0.0/16"}]}])
        self.assertEqual(find_open_management_port_rules(group), [])

    def test_open_http_is_not_flagged(self) -> None:
        group = sg([{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}])
        self.assertEqual(find_open_management_port_rules(group), [])

    def test_udp_on_22_is_not_flagged(self) -> None:
        group = sg([{"IpProtocol": "udp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}])
        self.assertEqual(find_open_management_port_rules(group), [])

    def test_a_clean_group_finds_nothing(self) -> None:
        self.assertEqual(find_open_management_port_rules(sg([])), [])

    def test_both_ssh_and_rdp_open_are_both_found(self) -> None:
        group = sg([
            {"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},
            {"IpProtocol": "tcp", "FromPort": 3389, "ToPort": 3389, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},
        ])
        self.assertEqual(len(find_open_management_port_rules(group)), 2)


class FakeEc2:
    def __init__(self) -> None:
        self.revoke_calls: list[dict[str, Any]] = []
        self.tag_calls: list[dict[str, Any]] = []

    def revoke_security_group_ingress(self, **kwargs: Any) -> dict[str, Any]:
        self.revoke_calls.append(kwargs)
        return {}

    def create_tags(self, **kwargs: Any) -> dict[str, Any]:
        self.tag_calls.append(kwargs)
        return {}

    def describe_security_groups(self, **kwargs: Any) -> dict[str, Any]:  # pragma: no cover - unused here
        return {"SecurityGroups": []}


class RevokeOpenRulesTests(unittest.TestCase):
    def test_ipv4_and_ipv6_rules_are_revoked_in_separate_calls(self) -> None:
        ec2 = FakeEc2()
        rules = [
            OpenRule("tcp", 22, 22, "0.0.0.0/0", False),
            OpenRule("tcp", 3389, 3389, "::/0", True),
        ]
        revoke_open_rules(ec2, "sg-open", rules)
        self.assertEqual(len(ec2.revoke_calls), 2)
        self.assertIn("IpRanges", ec2.revoke_calls[0]["IpPermissions"][0])
        self.assertIn("Ipv6Ranges", ec2.revoke_calls[1]["IpPermissions"][0])

    def test_the_group_is_tagged_remediated_by_auto(self) -> None:
        ec2 = FakeEc2()
        revoke_open_rules(ec2, "sg-open", [OpenRule("tcp", 22, 22, "0.0.0.0/0", False)])
        self.assertEqual(ec2.tag_calls[0]["Tags"], [{"Key": "remediated-by", "Value": "auto"}])
        self.assertEqual(ec2.tag_calls[0]["Resources"], ["sg-open"])

    def test_an_empty_rule_list_makes_no_revoke_call_but_still_tags(self) -> None:
        ec2 = FakeEc2()
        revoke_open_rules(ec2, "sg-open", [])
        self.assertEqual(ec2.revoke_calls, [])
        self.assertEqual(len(ec2.tag_calls), 1)


class ExtractGroupIdAndAccountTests(unittest.TestCase):
    def test_cloudtrail_derived_event_is_parsed(self) -> None:
        event = {
            "account": "222233334444",
            "detail": {"requestParameters": {"groupId": "sg-0123456789abcdef0"}},
        }
        self.assertEqual(extract_group_id_and_account(event), ("sg-0123456789abcdef0", "222233334444"))

    def test_missing_account_falls_back_to_recipient_account_id(self) -> None:
        event = {"detail": {"requestParameters": {"groupId": "sg-x"}, "recipientAccountId": "555566667777"}}
        self.assertEqual(extract_group_id_and_account(event), ("sg-x", "555566667777"))

    def test_an_unrecognised_event_shape_raises(self) -> None:
        with self.assertRaises(ValueError):
            extract_group_id_and_account({"detail": {}})


class FakeSts:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def assume_role(self, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        return {"Credentials": {"AccessKeyId": "AKIA...", "SecretAccessKey": "secret", "SessionToken": "token"}}


class AssumeRemediationRoleTests(unittest.TestCase):
    def test_the_role_arn_is_built_from_the_account_and_role_name(self) -> None:
        sts = FakeSts()
        assume_remediation_role(sts, "222233334444", "security-remediation")
        self.assertEqual(sts.calls[0]["RoleArn"], "arn:aws:iam::222233334444:role/security-remediation")
        self.assertEqual(sts.calls[0]["RoleSessionName"], "auto-remediation")

    def test_credentials_are_returned_in_the_shape_boto3_client_expects(self) -> None:
        sts = FakeSts()
        creds = assume_remediation_role(sts, "222233334444", "security-remediation")
        self.assertEqual(set(creds), {"aws_access_key_id", "aws_secret_access_key", "aws_session_token"})


class FakeSns:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def publish(self, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        return {}


class PublishSummaryTests(unittest.TestCase):
    def test_message_names_the_group_account_and_rule_count(self) -> None:
        sns = FakeSns()
        rules = [OpenRule("tcp", 22, 22, "0.0.0.0/0", False)]
        publish_summary(sns, "arn:aws:sns:eu-central-1:111122223333:security-alerts-alerts", "222233334444", "sg-open", rules, 12.3)
        message = sns.calls[0]["Message"]
        self.assertIn("sg-open", message)
        self.assertIn("222233334444", message)
        self.assertIn("removed 1 open rule", message)
        self.assertIn("12.3s", message)


if __name__ == "__main__":
    unittest.main()

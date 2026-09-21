"""Offline tests for the Day-0 bootstrap template (no AWS access): the apply role's permissions boundary
and the CI roles. Needs PyYAML, which cfn-lint installs."""
import json
import unittest
from pathlib import Path

import yaml

TEMPLATE = Path(__file__).resolve().parents[1] / "cloudformation" / "account-bootstrap.yaml"
POLICY_SIZE_LIMIT = 6144  # AWS: a managed policy may have at most 6,144 non-whitespace characters


class CfnLoader(yaml.SafeLoader):
    """Loads CloudFormation short-form tags (!Sub, !If, !Ref, ...) as {'!Tag': value}."""


def _tag(loader, suffix, node):
    if isinstance(node, yaml.ScalarNode):
        value = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node, deep=True)
    else:
        value = loader.construct_mapping(node, deep=True)
    return {"!" + suffix: value}


CfnLoader.add_multi_constructor("!", _tag)


def load():
    return yaml.load(TEMPLATE.read_text(encoding="utf-8"), Loader=CfnLoader)


def statements(deny_organizations: bool) -> list[dict]:
    """The boundary's statements with the DenyOrganizations condition resolved."""
    result = []
    for st in load()["Resources"]["ApplyBoundary"]["Properties"]["PolicyDocument"]["Statement"]:
        if "!If" in st:
            _, when_true, when_false = st["!If"]
            chosen = when_true if deny_organizations else when_false
            if isinstance(chosen, dict) and "!Ref" in chosen:  # AWS::NoValue
                continue
            st = chosen
        result.append(st)
    return result


def sids(deny_organizations: bool) -> set[str]:
    return {st["Sid"] for st in statements(deny_organizations)}


class ApplyBoundary(unittest.TestCase):
    def test_one_broad_allow_then_only_denies(self):
        for flag in (True, False):
            sts = statements(flag)
            self.assertEqual(sts[0]["Sid"], "AllowEverythingElse")
            self.assertEqual(sts[0]["Effect"], "Allow")
            self.assertTrue(all(s["Effect"] == "Deny" for s in sts[1:]), "a boundary only ever narrows: everything after the Allow is a Deny")

    def test_required_denies_are_always_on(self):
        required = {
            "DenyIdentityCenter",
            "DenyOrgDestruction",
            "DenyCloudTrailChanges",
            "DenyEditingThisBoundary",
            "DenyEditingCiRoles",
            "DenyEditingGithubOidcProvider",
            "DenySecurityServiceTampering",
            "DenyEditingPlatformRoles",
            "DenyDeletingWorkloadBoundary",
            "DenyRemovingAnyRoleBoundary",
            "ProtectStateBucket",
            "ProtectBootstrapStack",
        }
        for flag in (True, False):
            self.assertLessEqual(required, sids(flag), f"missing a required deny (DenyOrganizations={flag})")

    def test_organizations_are_denied_everywhere_except_where_allowed(self):
        self.assertIn("DenyOrganizationsAndAccount", sids(True))  # member accounts
        self.assertNotIn("DenyOrganizationsAndAccount", sids(False))  # management (AllowOrganizationsAdmin = true)
        deny = next(s for s in statements(True) if s["Sid"] == "DenyOrganizationsAndAccount")
        self.assertEqual(set(deny["Action"]), {"organizations:*", "account:*"})

    def test_security_services_cannot_be_switched_off(self):
        st = next(s for s in statements(True) if s["Sid"] == "DenySecurityServiceTampering")
        for action in ("guardduty:DeleteDetector", "config:StopConfigurationRecorder", "securityhub:DisableSecurityHub", "macie2:DisableMacie", "access-analyzer:DeleteAnalyzer", "inspector2:Disable"):
            self.assertIn(action, st["Action"])

    def test_platform_roles_are_protected_but_the_workload_boundary_can_still_be_updated(self):
        roles = next(s for s in statements(True) if s["Sid"] == "DenyEditingPlatformRoles")
        resources = json.dumps(roles["Resource"])
        for name in ("role/platform-*", "role/terraform-*", "role/OrganizationAccountAccessRole"):
            self.assertIn(name, resources)
        boundary = next(s for s in statements(True) if s["Sid"] == "DenyDeletingWorkloadBoundary")
        # The baseline stack updates platform-workload-boundary with CreatePolicyVersion, so that (and
        # SetDefaultPolicyVersion, DeletePolicyVersion) must stay allowed: only deleting it is denied.
        self.assertEqual(boundary["Action"], ["iam:DeletePolicy"])

    def test_policy_fits_the_aws_size_limit(self):
        for flag in (True, False):
            text = json.dumps({"Version": "2012-10-17", "Statement": statements(flag)}, separators=(",", ":"))
            size = len("".join(text.split()))
            # !Sub strings are a little longer once the account id and region are filled in
            self.assertLess(size + 400, POLICY_SIZE_LIMIT, f"boundary is {size} characters (limit {POLICY_SIZE_LIMIT}, DenyOrganizations={flag})")


class CiRoles(unittest.TestCase):
    def setUp(self):
        self.resources = load()["Resources"]

    def test_apply_role_is_capped_and_trusts_one_environment(self):
        role = self.resources["ApplyRole"]["Properties"]
        self.assertEqual(role["PermissionsBoundary"], {"!Ref": "ApplyBoundary"})
        self.assertEqual(role["MaxSessionDuration"], 3600)
        cond = role["AssumeRolePolicyDocument"]["Statement"][0]["Condition"]
        self.assertIn("token.actions.githubusercontent.com:sub", cond["StringEquals"], "the environment is matched exactly, never with a wildcard")
        self.assertNotIn("StringLike", cond)
        self.assertIn("environment:${GitHubEnvironment}", json.dumps(cond))

    def test_plan_role_is_read_only(self):
        role = self.resources["PlanRole"]["Properties"]
        self.assertEqual(role["ManagedPolicyArns"], ["arn:aws:iam::aws:policy/ReadOnlyAccess"])
        inline = role["Policies"][0]["PolicyDocument"]["Statement"]
        lock = next(s for s in inline if s["Sid"] == "StateLockWrite")
        self.assertIn("*.tflock", json.dumps(lock["Resource"]), "the plan role may only write lock files, never state")

    def test_state_bucket_is_retained_and_outputs_are_not_exported(self):
        template = load()
        bucket = template["Resources"]["StateBucket"]
        self.assertEqual(bucket["DeletionPolicy"], "Retain")
        self.assertEqual(bucket["UpdateReplacePolicy"], "Retain")
        for name, output in template["Outputs"].items():
            self.assertNotIn("Export", output, f"an export would lock {name}")


if __name__ == "__main__":
    unittest.main()

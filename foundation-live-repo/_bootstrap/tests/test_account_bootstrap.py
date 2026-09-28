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


def statements(deny_organizations: bool, deny_identity_center: bool = True) -> list[dict]:
    """The boundary's statements with the DenyOrganizations / DenyIdentityCenter conditions resolved.

    (True, True) is a member account; (False, False) is the management account, where the apply role
    manages Organizations and Identity Center."""
    conditions = {"DenyOrganizations": deny_organizations, "DenyIdentityCenter": deny_identity_center}
    result = []
    for st in load()["Resources"]["ApplyBoundary"]["Properties"]["PolicyDocument"]["Statement"]:
        if "!If" in st:
            name, when_true, when_false = st["!If"]
            chosen = when_true if conditions[name] else when_false
            if isinstance(chosen, dict) and "!Ref" in chosen:  # AWS::NoValue
                continue
            st = chosen
        result.append(st)
    return result


def sids(deny_organizations: bool, deny_identity_center: bool = True) -> set[str]:
    return {st["Sid"] for st in statements(deny_organizations, deny_identity_center)}


# member account, management account, and the two "one switch on" mixes
COMBINATIONS = [(True, True), (False, False), (False, True), (True, False)]


class ApplyBoundary(unittest.TestCase):
    def test_one_broad_allow_then_only_denies(self):
        for org, idc in COMBINATIONS:
            sts = statements(org, idc)
            self.assertEqual(sts[0]["Sid"], "AllowEverythingElse")
            self.assertEqual(sts[0]["Effect"], "Allow")
            self.assertTrue(all(s["Effect"] == "Deny" for s in sts[1:]), "a boundary only ever narrows: everything after the Allow is a Deny")

    def test_required_denies_are_always_on(self):
        required = {
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
        for org, idc in COMBINATIONS:
            self.assertLessEqual(required, sids(org, idc), f"missing a required deny (DenyOrganizations={org}, DenyIdentityCenter={idc})")

    def test_organizations_are_denied_everywhere_except_where_allowed(self):
        self.assertIn("DenyOrganizationsAndAccount", sids(True))  # member accounts
        self.assertNotIn("DenyOrganizationsAndAccount", sids(False))  # management (AllowOrganizationsAdmin = true)
        deny = next(s for s in statements(True) if s["Sid"] == "DenyOrganizationsAndAccount")
        self.assertEqual(set(deny["Action"]), {"organizations:*", "account:*"})

    def test_identity_center_is_denied_everywhere_except_where_allowed(self):
        # Member accounts (and the StackSets) never allow it; only management, where CI applies the identity-center stack.
        self.assertIn("DenyIdentityCenter", sids(True, True))
        self.assertNotIn("DenyIdentityCenter", sids(False, False))
        deny = next(s for s in statements(True, True) if s["Sid"] == "DenyIdentityCenter")
        self.assertEqual(set(deny["Action"]), {"sso:*", "sso-directory:*", "identitystore:*"})

    def test_the_two_switches_are_independent(self):
        # Allowing Identity Center must not allow Organizations, and the other way round.
        self.assertIn("DenyOrganizationsAndAccount", sids(True, False))
        self.assertNotIn("DenyIdentityCenter", sids(True, False))
        self.assertIn("DenyIdentityCenter", sids(False, True))
        self.assertNotIn("DenyOrganizationsAndAccount", sids(False, True))

    def test_org_destruction_is_denied_even_where_organizations_are_managed(self):
        deny = next(s for s in statements(False, False) if s["Sid"] == "DenyOrgDestruction")
        self.assertIn("organizations:DeleteOrganization", deny["Action"])

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
        for org, idc in COMBINATIONS:
            text = json.dumps({"Version": "2012-10-17", "Statement": statements(org, idc)}, separators=(",", ":"))
            size = len("".join(text.split()))
            # !Sub strings are a little longer once the account id and region are filled in
            self.assertLess(size + 400, POLICY_SIZE_LIMIT, f"boundary is {size} characters (limit {POLICY_SIZE_LIMIT}, DenyOrganizations={org}, DenyIdentityCenter={idc})")


class CiRoles(unittest.TestCase):
    def setUp(self):
        self.resources = load()["Resources"]

    def test_admin_switches_default_to_false_and_are_strings(self):
        params = load()["Parameters"]
        for name in ("AllowOrganizationsAdmin", "AllowIdentityCenterAdmin"):
            self.assertEqual(params[name]["Default"], "false", f"{name} must default to the safe value")
            self.assertEqual(params[name]["AllowedValues"], ["true", "false"])
        conditions = load()["Conditions"]
        self.assertEqual(conditions["DenyIdentityCenter"], {"!Equals": [{"!Ref": "AllowIdentityCenterAdmin"}, "false"]})

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


class StateReplication(unittest.TestCase):
    """PLAN 7.2: optional one-way copy of the state bucket to the secondary region."""

    def test_replication_is_off_unless_a_replica_arn_is_given(self):
        template = load()
        self.assertEqual(template["Parameters"]["ReplicaRegion"]["Default"], "")
        self.assertEqual(template["Resources"]["StateReplicationRole"]["Condition"], "ReplicateState")
        config = template["Resources"]["StateBucket"]["Properties"]["ReplicationConfiguration"]
        self.assertEqual(config["!If"][0], "ReplicateState")
        self.assertEqual(config["!If"][2], {"!Ref": "AWS::NoValue"})

    def test_deletes_are_not_replicated_and_the_role_is_scoped(self):
        template = load()
        rule = template["Resources"]["StateBucket"]["Properties"]["ReplicationConfiguration"]["!If"][1]["Rules"][0]
        self.assertEqual(rule["DeleteMarkerReplication"]["Status"], "Disabled", "the replica must survive a mistaken delete")
        role = template["Resources"]["StateReplicationRole"]["Properties"]
        text = json.dumps(role["Policies"])
        self.assertNotIn('"*"', text.replace('"/*"', ""), "no wildcard resource or action on the replication role")
        self.assertNotIn("s3:*", text)
        self.assertNotIn("!GetAtt", text, "using the bucket name (not GetAtt) avoids a circular dependency")

    def test_the_replica_regions_stack_creates_only_the_bucket_side(self):
        """Global IAM (OIDC provider, boundary, CI roles) must not be created a second time in the replica region."""
        template = load()
        for name in ["GitHubOidcProvider", "ApplyBoundary", "PlanRole", "ApplyRole"]:
            self.assertEqual(template["Resources"][name].get("Condition"), "CreateGlobalResources", name)
        for name in ["PlanRoleArn", "ApplyRoleArn", "OidcProviderArn"]:
            self.assertEqual(template["Outputs"][name].get("Condition"), "CreateGlobalResources", name)
        self.assertNotIn("Condition", template["Resources"]["StateBucket"], "the bucket exists in every region")


if __name__ == "__main__":
    unittest.main()

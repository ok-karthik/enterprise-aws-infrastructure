import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import plan_scope as p  # noqa: E402


class PlanScope(unittest.TestCase):
    def test_anything_but_a_pull_request_is_a_full_run(self):
        for event in ["push", "schedule", "workflow_dispatch", ""]:
            self.assertEqual(p.decide(event, ["workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/x/terragrunt.hcl"]), "full")

    def test_a_change_inside_one_unit_is_affected_only(self):
        self.assertEqual(p.decide("pull_request", ["workloads-live-repo/workloads/prod/workloads-prod/eu-west-1/network/vpc/terragrunt.hcl"]), "affected")

    def test_shared_code_forces_a_full_run(self):
        for path in [
            "iac-modules-repo/network/vpc/main.tf",
            "workloads-live-repo/_envcommon/network/vpc.hcl",
            "foundation-live-repo/_config/regions.hcl",
            "workloads-live-repo/root.hcl",
            ".github/workflows/terragrunt.yml",
            "policy-library-repo/terraform/require_tags.rego",
            ".checkov.yaml",
        ]:
            self.assertEqual(p.decide("pull_request", ["docs/x.md", path]), "full", path)

    def test_docs_only_pr_is_affected_and_plans_nothing(self):
        self.assertEqual(p.decide("pull_request", ["docs/ARCHITECTURE.md", "README.md"]), "affected")


if __name__ == "__main__":
    unittest.main()

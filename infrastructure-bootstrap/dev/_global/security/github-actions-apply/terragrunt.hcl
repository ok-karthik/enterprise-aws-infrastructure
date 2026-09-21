# Role assumed by CI jobs that APPLY (and destroy). It can only be assumed from a job that runs
# in the `dev` or `prod` GitHub Environment, so the prod approval gate cannot be skipped by a
# branch or a pull request. AdministratorAccess for now (PLAN 3.4 narrows it), capped by the
# github-actions-apply-boundary permissions boundary.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/iam/aws//modules/iam-role?version=6.6.0"
}

dependencies {
  paths = ["../github-oidc-provider"]
}

dependency "boundary" {
  config_path = "../github-actions-boundary"

  mock_outputs = {
    arn = "arn:aws:iam::123456789012:policy/github-actions-apply-boundary"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

locals {
  # The GitHub repository that is allowed to assume this role
  github_repo = "ok-karthik/enterprise-aws-infrastructure"
}

inputs = {
  name            = "github-actions-apply"
  use_name_prefix = false
  description     = "GitHub Actions: terragrunt apply/destroy (dev and prod GitHub Environments only)"

  max_session_duration = 3600

  enable_github_oidc = true
  oidc_subjects = [
    "${local.github_repo}:environment:dev",
    "${local.github_repo}:environment:prod",
  ]

  permissions_boundary = dependency.boundary.outputs.arn

  policies = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  tags = {
    Role = "github-actions-apply"
  }
}

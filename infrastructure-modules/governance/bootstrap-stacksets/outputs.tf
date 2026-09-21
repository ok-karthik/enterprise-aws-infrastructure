output "stack_set_names" {
  description = "Names of the bootstrap StackSets, keyed by name"
  value       = { for name, s in aws_cloudformation_stack_set.this : name => s.name }
}

output "stack_set_arns" {
  description = "ARNs of the bootstrap StackSets, keyed by name"
  value       = { for name, s in aws_cloudformation_stack_set.this : name => s.arn }
}

output "github_environments" {
  description = "GitHub Environment each StackSet trusts for github-actions-apply, keyed by StackSet name"
  value       = { for name, s in var.stack_sets : name => s.github_environment }
}

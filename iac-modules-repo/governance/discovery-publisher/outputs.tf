output "parameter_names" {
  description = "Full names of the published parameters, keyed by contract key"
  value       = { for key, p in aws_ssm_parameter.this : key => p.name }
}

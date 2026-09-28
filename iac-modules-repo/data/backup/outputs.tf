output "vault_arn" {
  description = "ARN of the backup vault in this region (pass it as copy_destination_vault_arn to the primary region's stack)"
  value       = aws_backup_vault.this.arn
}

output "vault_name" {
  description = "Name of the backup vault in this region"
  value       = aws_backup_vault.this.name
}

output "plan_id" {
  description = "Backup plan ID. Empty when create_plan is false."
  value       = try(aws_backup_plan.this[0].id, "")
}

output "cluster_identifier" {
  description = "Aurora cluster identifier in this region"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.this.arn
}

output "writer_endpoint" {
  description = "Cluster (writer) endpoint. On a global_secondary it is read-only until that cluster is promoted."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Load-balanced read-only endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "global_cluster_identifier" {
  description = "Global cluster to pass to the secondary region's stack. Empty in standalone mode."
  value       = var.mode == "global_primary" ? aws_rds_global_cluster.this[0].id : var.global_cluster_identifier
}

output "master_secret_arn" {
  description = "Secrets Manager ARN of the master credentials: RDS-managed (standalone) or module-created (global_primary). Empty on a secondary."
  value = (
    var.mode == "standalone" ? try(aws_rds_cluster.this.master_user_secret[0].secret_arn, "") :
    var.mode == "global_primary" ? aws_secretsmanager_secret.master[0].arn : ""
  )
}

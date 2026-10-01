output "cur_bucket_name" {
  description = "Bucket that receives the CUR 2.0 export (point Athena at s3://<bucket>/cur2/)"
  value       = aws_s3_bucket.cur.id
}

output "export_arn" {
  description = "ARN of the Data Exports export"
  value       = aws_bcmdataexports_export.cur.arn
}

output "anomaly_monitor_arns" {
  description = "ARNs of all anomaly monitors (the organization-wide one and one per OU)"
  value       = concat([aws_ce_anomaly_monitor.services.arn], [for m in aws_ce_anomaly_monitor.ou : m.arn])
}

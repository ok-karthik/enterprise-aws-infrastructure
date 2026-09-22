output "trail_arn" {
  description = "ARN of the organization trail"
  value       = aws_cloudtrail.org.arn
}

output "trail_name" {
  description = "Name of the organization trail"
  value       = aws_cloudtrail.org.name
}

output "home_region" {
  description = "Region the trail was created in (its home region; the trail itself covers every region)"
  value       = aws_cloudtrail.org.home_region
}

output "cloudtrail_lake_arn" {
  description = "ARN of the CloudTrail Lake event data store, or null when enable_cloudtrail_lake is false"
  value       = try(aws_cloudtrail_event_data_store.org[0].arn, null)
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Logs group the trail delivers to"
  value       = aws_cloudwatch_log_group.org_trail.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic that receives CloudTrail's log-delivery notifications"
  value       = aws_sns_topic.trail_notifications.arn
}

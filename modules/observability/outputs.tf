output "trail_bucket_name" {
  value = aws_s3_bucket.trail.id
}

output "trail_arn" {
  value = aws_cloudtrail.main.arn
}

output "flow_log_group" {
  value = aws_cloudwatch_log_group.vpc_flow.name
}

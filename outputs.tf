output "vpc_id" {
  value = module.network.vpc_id
}

output "private_instance_id" {
  value = module.compute.instance_id
}

output "private_instance_ip" {
  value = module.compute.private_ip
}

output "ssm_session_command" {
  description = "Requires ssm:StartSession and the Session Manager plugin."
  value       = "aws ssm start-session --target ${module.compute.instance_id} --region ${var.aws_region}"
}

output "bastion_public_ip" {
  value = module.compute.bastion_public_ip
}

output "cloudtrail_bucket_name" {
  value = try(module.observability[0].trail_bucket_name, null)
}

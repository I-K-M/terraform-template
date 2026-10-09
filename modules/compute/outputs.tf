output "instance_id" {
  value = aws_instance.workload.id
}

output "private_ip" {
  value = aws_instance.workload.private_ip
}

output "bastion_public_ip" {
  value = try(aws_instance.bastion[0].public_ip, null)
}

output "workload_public_ip_enabled" {
  value = aws_instance.workload.associate_public_ip_address
}

output "workload_imdsv2_required" {
  value = aws_instance.workload.metadata_options[0].http_tokens
}

output "workload_ebs_encrypted" {
  value = aws_instance.workload.root_block_device[0].encrypted
}

output "workload_security_group_id" {
  value = aws_security_group.workload.id
}

output "bastion_security_group_id" {
  value = try(aws_security_group.bastion[0].id, null)
}

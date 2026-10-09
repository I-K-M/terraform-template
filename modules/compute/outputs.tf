output "instance_id" {
  value = aws_instance.workload.id
}

output "private_ip" {
  value = aws_instance.workload.private_ip
}

output "bastion_public_ip" {
  value = try(aws_instance.bastion[0].public_ip, null)
}

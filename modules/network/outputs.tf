output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "public_subnet_id" {
  value = try(aws_subnet.public[0].id, null)
}

output "endpoint_security_group_id" {
  value = aws_security_group.endpoints.id
}

output "s3_prefix_list_id" {
  value = aws_vpc_endpoint.s3.prefix_list_id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

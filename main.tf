provider "aws" {
  region = "eu-west-3"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.20.0.0/16"
}

# Public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "eu-west-3a"
  map_public_ip_on_launch = true
}

# Network ACL for Public Subnet (Bastion)
resource "aws_network_acl" "public_nacl" {
  vpc_id = aws_vpc.main.id
  subnet_ids = [aws_subnet.public_subnet.id]
  tags = {
    Name = "PublicSubnetNACL"
  }
}

# Inbound rules (allow SSH and ephemeral ports)
resource "aws_network_acl_rule" "public_inbound_ssh" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.my_ip
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "public_inbound_ephemeral" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Outbound rules
resource "aws_network_acl_rule" "public_outbound_all" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# Private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "eu-west-3a"
}

# Network ACL for Private Subnet
resource "aws_network_acl" "private_nacl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_subnet.id]
  tags = {
    Name = "PrivateSubnetNACL"
  }
}

# Inbound (from Bastion on port 22)
resource "aws_network_acl_rule" "private_inbound_ssh" {
  network_acl_id = aws_network_acl.private_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.20.1.0/24" # subnet public
  from_port      = 22
  to_port        = 22
}

# Outbound (ephemeral ports to respond to SSH)
resource "aws_network_acl_rule" "private_outbound_ephemeral" {
  network_acl_id = aws_network_acl.private_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.20.1.0/24"
  from_port      = 1024
  to_port        = 65535
}


# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# Elastic IP
resource "aws_eip" "nat_eip" {
}

# NAT gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [aws_internet_gateway.gw]
}

# Route tables
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

# Link table to subnets
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# EC2 in public subnet
resource "aws_instance" "bastion" {
  ami                         = "ami-01032886170466a16"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  key_name                    = "mykey"

  vpc_security_group_ids = [aws_security_group.ssh.id]

  tags = {
    Name = "BastionHost"
  }
}

# Public EC2 SG: allow ssh
resource "aws_security_group" "ssh" {
  name        = "allow_ssh"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["PUBLIC_IP/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 in private subnet
resource "aws_instance" "web" {
  ami           = "ami-01032886170466a16"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private_subnet.id
  key_name      = "mykey"

  vpc_security_group_ids = [aws_security_group.private_sg.id]

  tags = {
    Name = "WebServer"
  }
}

# Private EC2 SG
resource "aws_security_group" "private_sg" {
  name   = "allow_from_bastion"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # authorise bastion only
    security_groups = [aws_security_group.ssh.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# S3 bucket endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-3.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.rt.id,
    aws_route_table.private_rt.id
  ]
}

# Outputs
output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}

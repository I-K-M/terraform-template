data "aws_ssm_parameter" "ubuntu" {
  count = var.ami_id == null ? 1 : 0
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  image_id = var.ami_id == null ? data.aws_ssm_parameter.ubuntu[0].value : var.ami_id
}

resource "aws_iam_role" "ssm" {
  name_prefix = "${var.name_prefix}-ssm-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name_prefix = "${var.name_prefix}-instance-"
  role = aws_iam_role.ssm.name
}

resource "aws_security_group" "workload" {
  name_prefix = "${var.name_prefix}-workload-"
  description = "No inbound ports; SSM outbound only by default"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-workload" }
}

resource "aws_vpc_security_group_egress_rule" "ssm" {
  security_group_id            = aws_security_group.workload.id
  referenced_security_group_id = var.endpoint_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Only HTTPS to SSM VPC endpoints"
}

resource "aws_vpc_security_group_egress_rule" "s3" {
  security_group_id = aws_security_group.workload.id
  prefix_list_id    = var.s3_prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to regional S3 through gateway endpoint"
}

# Opt-in only: permits OS updates and external services through the NAT gateway.
resource "aws_vpc_security_group_egress_rule" "https_internet" {
  count             = var.enable_nat_gateway ? 1 : 0
  security_group_id = aws_security_group.workload.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Optional HTTPS egress via NAT"
}

resource "aws_instance" "workload" {
  ami                         = local.image_id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  vpc_security_group_ids      = [aws_security_group.workload.id]
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = "${var.name_prefix}-private" }
}

resource "aws_security_group" "bastion" {
  count       = var.enable_bastion ? 1 : 0
  name_prefix = "${var.name_prefix}-bastion-"
  description = "Optional restricted SSH bastion; disabled by default"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-bastion" }

  lifecycle {
    precondition {
      condition     = var.bastion_allowed_cidr != null && var.bastion_key_name != null
      error_message = "Enabling bastion requires an existing key name and bastion_allowed_cidr /32."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  count             = var.enable_bastion ? 1 : 0
  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = var.bastion_allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "SSH from explicitly approved single source"
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_workload" {
  count                        = var.enable_bastion ? 1 : 0
  security_group_id            = aws_security_group.bastion[0].id
  referenced_security_group_id = aws_security_group.workload.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "SSH to private workload"
}

resource "aws_vpc_security_group_ingress_rule" "workload_bastion" {
  count                        = var.enable_bastion ? 1 : 0
  security_group_id            = aws_security_group.workload.id
  referenced_security_group_id = aws_security_group.bastion[0].id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "SSH only from optional bastion security group"
}

resource "aws_instance" "bastion" {
  count                       = var.enable_bastion ? 1 : 0
  ami                         = local.image_id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  associate_public_ip_address = true
  key_name                    = var.bastion_key_name
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  monitoring                  = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    delete_on_termination = true
  }
  tags = { Name = "${var.name_prefix}-bastion" }
}

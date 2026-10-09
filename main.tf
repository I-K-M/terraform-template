locals {
  name_prefix = "tf-platform-${var.environment}"
}

module "network" {
  source             = "./modules/network"
  name_prefix        = local.name_prefix
  region             = var.aws_region
  vpc_cidr           = var.vpc_cidr
  availability_zone  = var.availability_zone
  enable_nat_gateway = var.enable_nat_gateway
  enable_bastion     = var.enable_bastion
}

module "compute" {
  source                     = "./modules/compute"
  name_prefix                = local.name_prefix
  vpc_id                     = module.network.vpc_id
  private_subnet_id          = module.network.private_subnet_id
  public_subnet_id           = module.network.public_subnet_id
  endpoint_security_group_id = module.network.endpoint_security_group_id
  s3_prefix_list_id          = module.network.s3_prefix_list_id
  instance_type              = var.instance_type
  ami_id                     = var.ami_id
  ebs_kms_key_arn            = var.ebs_kms_key_arn
  enable_nat_gateway         = var.enable_nat_gateway
  enable_bastion             = var.enable_bastion
  bastion_allowed_cidr       = var.bastion_allowed_cidr
  bastion_key_name           = var.bastion_key_name
}

module "observability" {
  count                = var.enable_observability ? 1 : 0
  source               = "./modules/observability"
  name_prefix          = local.name_prefix
  region               = var.aws_region
  aws_account_id       = var.aws_account_id
  vpc_id               = module.network.vpc_id
  alert_email          = var.alert_email
  audit_s3_bucket_arns = var.audit_s3_bucket_arns
}

# Restrict PrivateLink access to the approved instance security groups.
# Kept at root to avoid a circular dependency between network and compute.
resource "aws_vpc_security_group_ingress_rule" "ssm_from_workload" {
  security_group_id            = module.network.endpoint_security_group_id
  referenced_security_group_id = module.compute.workload_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "SSM PrivateLink from managed workload only"
}

resource "aws_vpc_security_group_ingress_rule" "ssm_from_bastion" {
  count                        = var.enable_bastion ? 1 : 0
  security_group_id            = module.network.endpoint_security_group_id
  referenced_security_group_id = module.compute.bastion_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "SSM PrivateLink from optional managed bastion"
}

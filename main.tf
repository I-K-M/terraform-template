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

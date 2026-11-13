data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ubuntu_ami_name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

module "network" {
  source             = "./modules/network"
  resource_prefix    = var.resource_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  nat_instance_type  = var.nat_instance_type
  nat_ami_id         = data.aws_ami.ubuntu.id
  ssh_allowed_cidr   = var.ssh_allowed_cidr
}

module "storage" {
  source                = "./modules/storage"
  resource_prefix       = var.resource_prefix
  backup_retention_days = var.backup_retention_days
}

module "secrets" {
  source              = "./modules/secrets"
  resource_prefix     = var.resource_prefix
  password_min_length = var.password_min_length
}

module "iam" {
  source             = "./modules/iam"
  resource_prefix    = var.resource_prefix
  bucket_arn         = module.storage.bucket_arn
  ecr_repository_arn = module.storage.ecr_repository_arn
  secret_arns        = module.secrets.secret_arns
  aws_account_id     = data.aws_caller_identity.current.account_id
  aws_region         = var.aws_region
  github_org_repo    = var.github_org_repo
}

module "database" {
  source                   = "./modules/database"
  resource_prefix          = var.resource_prefix
  ami_id                   = data.aws_ami.ubuntu.id
  db_subnet_ids            = module.network.db_subnet_ids
  availability_zones       = var.availability_zones
  sg_db_id                 = module.network.sg_db_id
  instance_profile_name    = module.iam.db_instance_profile_name
  primary_instance_type    = var.db_instance_type
  replica_instance_type    = var.db_replica_instance_type
  clickhouse_instance_type = var.clickhouse_instance_type
  clickhouse_required      = var.clickhouse_required
  password_min_length      = var.password_min_length
  backup_retention_days    = var.backup_retention_days
  rpo_minutes              = var.rpo_minutes
  bucket_name              = module.storage.bucket_name
  secret_names             = module.secrets.secret_names
  aws_region               = var.aws_region
}

module "compute" {
  source                = "./modules/compute"
  resource_prefix       = var.resource_prefix
  ami_id                = data.aws_ami.ubuntu.id
  app_subnet_ids        = module.network.app_subnet_ids
  availability_zones    = var.availability_zones
  sg_k3s_id             = module.network.sg_k3s_id
  instance_profile_name = module.iam.node_instance_profile_name
  server_instance_type  = var.k3s_server_instance_type
  agent_instance_type   = var.k3s_agent_instance_type
  agent_min             = var.k3s_agent_min
  agent_max             = var.k3s_agent_max
  agent_desired         = var.k3s_agent_desired
  aws_region            = var.aws_region
  secret_k3s_token      = module.secrets.k3s_token_secret_name
  ecr_repository_url    = module.storage.ecr_repository_url
  alert_cpu_pct         = var.alert_cpu_pct
}

module "loadbalancer" {
  source            = "./modules/loadbalancer"
  resource_prefix   = var.resource_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  sg_alb_id         = module.network.sg_alb_id
  k3s_asg_name      = module.compute.asg_name
  k3s_server_id     = module.compute.k3s_server_id
}

module "monitoring" {
  source            = "./modules/monitoring"
  resource_prefix   = var.resource_prefix
  aws_region        = var.aws_region
  alert_email       = var.budget_alert_email
  alert_cpu_pct     = var.alert_cpu_pct
  alert_5xx_per_min = var.alert_5xx_per_min
  asg_name          = module.compute.asg_name
  alb_arn_suffix    = regex("app/.*$", module.loadbalancer.alb_arn)
  tg_arn_suffix     = regex("targetgroup/.*$", module.loadbalancer.target_group_arn)
  mysql_primary_id  = module.database.mysql_primary_id
}

module "budget" {
  source             = "./modules/budget"
  resource_prefix    = var.resource_prefix
  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.budget_alert_email
}

variable "github_org_repo" {
  type        = string
  description = "GitHub owner/repo for OIDC (set after creating the public repo)"
  default     = ""
}

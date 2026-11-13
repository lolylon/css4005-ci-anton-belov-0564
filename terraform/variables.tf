variable "resource_prefix" {
  type        = string
  description = "Prefix for every resource name and Project tag"
  default     = "ci-anton-belov-0564"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.195.0.0/16"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "app_name" {
  type    = string
  default = "Library books"
}

variable "app_owner" {
  type        = string
  description = "Shown on the app home page"
  default     = "Anton Belov (0564)"
}

variable "monthly_budget_usd" {
  type    = number
  default = 15
}

variable "budget_alert_email" {
  type        = string
  description = "Email for AWS Budgets and CloudWatch alarm notifications"
}

variable "db_engine" {
  type    = string
  default = "mysql"
}

variable "clickhouse_required" {
  type    = bool
  default = true
}

variable "hpa_cpu_target" {
  type    = number
  default = 60
}

variable "password_min_length" {
  type    = number
  default = 14
}

variable "password_require_symbol" {
  type    = bool
  default = true
}

variable "alert_cpu_pct" {
  type    = number
  default = 80
}

variable "alert_5xx_per_min" {
  type    = number
  default = 20
}

variable "backup_retention_days" {
  type    = number
  default = 30
}

variable "rpo_minutes" {
  type    = number
  default = 15
}

variable "rto_minutes" {
  type    = number
  default = 30
}

variable "traffic_pattern" {
  type    = string
  default = "spiky"
}

variable "cluster_type" {
  type    = string
  default = "k3s-on-autoscaled-vms"
}

variable "k3s_server_instance_type" {
  type    = string
  default = "t3.small"
}

variable "k3s_agent_instance_type" {
  type    = string
  default = "t3.small"
}

variable "k3s_agent_min" {
  type    = number
  default = 2
}

variable "k3s_agent_max" {
  type    = number
  default = 4
}

variable "k3s_agent_desired" {
  type    = number
  default = 2
}

variable "db_instance_type" {
  type    = string
  default = "t3.small"
}

variable "db_replica_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "clickhouse_instance_type" {
  type    = string
  default = "t3.small"
}

variable "nat_instance_type" {
  type        = string
  description = "Cost-saving NAT EC2 instead of NAT Gateway (~$32/mo); Free Tier requires t3.micro+"
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "Optional bastion/SSH. Empty = SSM only, no SSH from internet."
  default     = ""
}

variable "ami_owner" {
  type    = string
  default = "amazon"
}

variable "ubuntu_ami_name" {
  type        = string
  description = "Ubuntu 22.04 LTS amd64 HVM SSD"
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

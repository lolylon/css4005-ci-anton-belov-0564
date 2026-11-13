variable "resource_prefix" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" { type = list(string) }
variable "nat_instance_type" { type = string }
variable "nat_ami_id" { type = string }
variable "ssh_allowed_cidr" {
  type    = string
  default = ""
}

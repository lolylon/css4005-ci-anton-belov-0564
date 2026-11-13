variable "resource_prefix" { type = string }
variable "ami_id" { type = string }
variable "db_subnet_ids" { type = list(string) }
variable "availability_zones" { type = list(string) }
variable "sg_db_id" { type = string }
variable "instance_profile_name" { type = string }
variable "primary_instance_type" { type = string }
variable "replica_instance_type" { type = string }
variable "clickhouse_instance_type" { type = string }
variable "clickhouse_required" { type = bool }
variable "password_min_length" { type = number }
variable "backup_retention_days" { type = number }
variable "rpo_minutes" { type = number }
variable "bucket_name" { type = string }
variable "secret_names" { type = map(string) }
variable "aws_region" { type = string }

locals {
  primary_user_data = base64encode(templatefile("${path.module}/../../../scripts/mysql-primary.sh", {
    resource_prefix       = var.resource_prefix
    aws_region            = var.aws_region
    bucket_name           = var.bucket_name
    password_min_length   = var.password_min_length
    backup_retention_days = var.backup_retention_days
    rpo_minutes           = var.rpo_minutes
    secret_admin          = var.secret_names["db-admin"]
    secret_app_rw         = var.secret_names["db-app-rw"]
    secret_app_ro         = var.secret_names["db-app-ro"]
    secret_repl           = var.secret_names["db-repl"]
  }))

  clickhouse_user_data = base64encode(templatefile("${path.module}/../../../scripts/clickhouse.sh", {
    resource_prefix   = var.resource_prefix
    aws_region        = var.aws_region
    secret_clickhouse = var.secret_names["clickhouse"]
  }))
}

resource "aws_ebs_volume" "primary_data" {
  availability_zone = var.availability_zones[0]
  size              = 20
  type              = "gp3"
  encrypted         = true
  tags = {
    Name = "${var.resource_prefix}-mysql-primary-data"
    Role = "mysql-primary-data"
  }
}

resource "aws_ebs_volume" "replica_data" {
  availability_zone = var.availability_zones[1]
  size              = 20
  type              = "gp3"
  encrypted         = true
  tags = {
    Name = "${var.resource_prefix}-mysql-replica-data"
    Role = "mysql-replica-data"
  }
}

resource "aws_ebs_volume" "clickhouse_data" {
  count             = var.clickhouse_required ? 1 : 0
  availability_zone = var.availability_zones[0]
  size              = 20
  type              = "gp3"
  encrypted         = true
  tags = {
    Name = "${var.resource_prefix}-clickhouse-data"
    Role = "clickhouse-data"
  }
}

resource "aws_instance" "mysql_primary" {
  ami                    = var.ami_id
  instance_type          = var.primary_instance_type
  subnet_id              = var.db_subnet_ids[0]
  vpc_security_group_ids = [var.sg_db_id]
  iam_instance_profile   = var.instance_profile_name
  user_data_base64       = local.primary_user_data

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.resource_prefix}-mysql-primary"
    Role = "mysql-primary"
  }
}

resource "aws_volume_attachment" "primary_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.primary_data.id
  instance_id = aws_instance.mysql_primary.id
}

resource "aws_instance" "mysql_replica" {
  ami                    = var.ami_id
  instance_type          = var.replica_instance_type
  subnet_id              = var.db_subnet_ids[1]
  vpc_security_group_ids = [var.sg_db_id]
  iam_instance_profile   = var.instance_profile_name
  # Replica script reads primary private IP from tag/SSM param written after primary is up
  user_data_base64 = base64encode(templatefile("${path.module}/../../../scripts/mysql-replica.sh", {
    resource_prefix    = var.resource_prefix
    aws_region         = var.aws_region
    secret_repl        = var.secret_names["db-repl"]
    secret_admin       = var.secret_names["db-admin"]
    primary_private_ip = aws_instance.mysql_primary.private_ip
  }))

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  depends_on = [aws_instance.mysql_primary]

  tags = {
    Name = "${var.resource_prefix}-mysql-replica"
    Role = "mysql-replica"
  }
}

resource "aws_volume_attachment" "replica_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.replica_data.id
  instance_id = aws_instance.mysql_replica.id
}

resource "aws_instance" "clickhouse" {
  count                  = var.clickhouse_required ? 1 : 0
  ami                    = var.ami_id
  instance_type          = var.clickhouse_instance_type
  subnet_id              = var.db_subnet_ids[0]
  vpc_security_group_ids = [var.sg_db_id]
  iam_instance_profile   = var.instance_profile_name
  user_data_base64       = local.clickhouse_user_data

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.resource_prefix}-clickhouse"
    Role = "clickhouse"
  }
}

resource "aws_volume_attachment" "clickhouse_data" {
  count       = var.clickhouse_required ? 1 : 0
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.clickhouse_data[0].id
  instance_id = aws_instance.clickhouse[0].id
}

# Snapshots every 15 minutes (RPO) with 30-day retention via DLM
resource "aws_iam_role" "dlm" {
  name = "${var.resource_prefix}-role-dlm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dlm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "db_data" {
  description        = "${var.resource_prefix} DB data disk hourly snapshots"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      Project = var.resource_prefix
    }

    # DLM min interval = 1h. RPO 15m is met by mysqldump cron (scripts/backup-mysql.sh).
    schedule {
      name = "hourly-db-data"

      create_rule {
        interval      = 1
        interval_unit = "HOURS"
        times         = ["00:00"]
      }

      retain_rule {
        interval      = var.backup_retention_days
        interval_unit = "DAYS"
      }

      tags_to_add = {
        SnapshotType = "dlm-db-data"
        Project      = var.resource_prefix
      }

      copy_tags = true
    }
  }

  tags = { Name = "${var.resource_prefix}-dlm-db" }
}

# Note: AWS DLM create_rule interval minimum is 1 hour. RPO 15 min is met by
# scripts/backup-mysql.sh cron every 15 minutes uploading mysqldump to S3.
# We still keep hourly EBS snapshots for crash-consistent disk recovery.

output "mysql_primary_private_ip" { value = aws_instance.mysql_primary.private_ip }
output "mysql_primary_id" { value = aws_instance.mysql_primary.id }
output "mysql_replica_private_ip" { value = aws_instance.mysql_replica.private_ip }
output "mysql_replica_id" { value = aws_instance.mysql_replica.id }
output "clickhouse_private_ip" {
  value = var.clickhouse_required ? aws_instance.clickhouse[0].private_ip : ""
}
output "clickhouse_id" {
  value = var.clickhouse_required ? aws_instance.clickhouse[0].id : ""
}
output "primary_data_volume_id" { value = aws_ebs_volume.primary_data.id }

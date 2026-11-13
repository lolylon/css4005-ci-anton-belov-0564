variable "resource_prefix" { type = string }
variable "password_min_length" { type = number }

resource "random_password" "admin" {
  length           = max(var.password_min_length, 20)
  special          = true
  override_special = "!@#%^*()-_=+"
  min_special      = 1
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

resource "random_password" "app_rw" {
  length           = max(var.password_min_length, 20)
  special          = true
  override_special = "!@#%^*()-_=+"
  min_special      = 1
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

resource "random_password" "app_ro" {
  length           = max(var.password_min_length, 20)
  special          = true
  override_special = "!@#%^*()-_=+"
  min_special      = 1
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

resource "random_password" "repl" {
  length           = max(var.password_min_length, 20)
  special          = true
  override_special = "!@#%^*()-_=+"
  min_special      = 1
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

resource "random_password" "clickhouse" {
  length           = max(var.password_min_length, 20)
  special          = true
  override_special = "!@#%^*()-_=+"
  min_special      = 1
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

resource "random_password" "secret_key" {
  length  = 48
  special = false
}

resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

locals {
  secrets = {
    "db-admin"       = random_password.admin.result
    "db-app-rw"      = random_password.app_rw.result
    "db-app-ro"      = random_password.app_ro.result
    "db-repl"        = random_password.repl.result
    "clickhouse"     = random_password.clickhouse.result
    "app-secret-key" = random_password.secret_key.result
    "k3s-token"      = random_password.k3s_token.result
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets
  name     = "${var.resource_prefix}/${each.key}"
  tags     = { Name = "${var.resource_prefix}/${each.key}" }
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each      = local.secrets
  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value
}

output "secret_arns" {
  value = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "secret_names" {
  value = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}

# Passwords are sensitive; never put them in outputs that CI prints.
output "k3s_token_secret_name" {
  value = aws_secretsmanager_secret.this["k3s-token"].name
}

output "app_rw_secret_name" {
  value = aws_secretsmanager_secret.this["db-app-rw"].name
}

output "secret_key_secret_name" {
  value = aws_secretsmanager_secret.this["app-secret-key"].name
}

output "clickhouse_secret_name" {
  value = aws_secretsmanager_secret.this["clickhouse"].name
}

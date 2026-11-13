output "resource_prefix" { value = var.resource_prefix }
output "vpc_id" { value = module.network.vpc_id }
output "vpc_cidr" { value = module.network.vpc_cidr }
output "subnet_cidrs" { value = module.network.subnet_cidrs }
output "alb_dns_name" { value = module.loadbalancer.alb_dns_name }
output "app_url" { value = "https://${module.loadbalancer.alb_dns_name}" }
output "bucket_name" { value = module.storage.bucket_name }
output "ecr_repository_url" { value = module.storage.ecr_repository_url }
output "mysql_primary_private_ip" { value = module.database.mysql_primary_private_ip }
output "mysql_replica_private_ip" { value = module.database.mysql_replica_private_ip }
output "clickhouse_private_ip" { value = module.database.clickhouse_private_ip }
output "k3s_server_private_ip" { value = module.compute.k3s_server_private_ip }
output "asg_name" { value = module.compute.asg_name }
output "dashboard_name" { value = module.monitoring.dashboard_name }
output "budget_name" { value = module.budget.budget_name }
output "gha_role_arn" { value = module.iam.gha_role_arn }
output "sns_topic_arn" { value = module.monitoring.sns_topic_arn }

output "app_env_hints" {
  description = "Non-secret wiring hints for K8s ConfigMap"
  value = {
    APP_NAME            = var.app_name
    APP_OWNER           = var.app_owner
    STORAGE_BACKEND     = "s3"
    BUCKET              = module.storage.bucket_name
    PASSWORD_MIN_LENGTH = tostring(var.password_min_length)
    DB_HOST             = module.database.mysql_primary_private_ip
    CLICKHOUSE_HOST     = module.database.clickhouse_private_ip
    HPA_CPU_TARGET      = tostring(var.hpa_cpu_target)
  }
}

variable "resource_prefix" { type = string }
variable "aws_region" { type = string }
variable "alert_email" { type = string }
variable "alert_cpu_pct" { type = number }
variable "alert_5xx_per_min" { type = number }
variable "asg_name" { type = string }
variable "alb_arn_suffix" { type = string }
variable "tg_arn_suffix" { type = string }
variable "mysql_primary_id" { type = string }

resource "aws_sns_topic" "alerts" {
  name = "${var.resource_prefix}-alerts"
  tags = { Name = "${var.resource_prefix}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.resource_prefix}/app"
  retention_in_days = 30
  tags              = { Name = "${var.resource_prefix}-app-logs" }
}

resource "aws_cloudwatch_log_group" "db" {
  name              = "/${var.resource_prefix}/db"
  retention_in_days = 30
  tags              = { Name = "${var.resource_prefix}-db-logs" }
}

# 1) ASG CPU above variant threshold
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.resource_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.alert_cpu_pct
  alarm_description   = "ASG/node CPU above ${var.alert_cpu_pct}%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

# 2) ALB 5xx per minute above variant threshold
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.resource_prefix}-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alert_5xx_per_min
  alarm_description   = "5xx per minute above ${var.alert_5xx_per_min}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# 3) Unhealthy targets
resource "aws_cloudwatch_metric_alarm" "unhealthy" {
  alarm_name          = "${var.resource_prefix}-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "ALB has unhealthy targets"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }
}

# 4) MySQL primary status check failed (proxy for disk/host issues)
resource "aws_cloudwatch_metric_alarm" "mysql_status" {
  alarm_name          = "${var.resource_prefix}-mysql-status"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "MySQL primary instance status check failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = var.mysql_primary_id
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.resource_prefix}-main"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB requests / 5xx / latency"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "Requests" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { stat = "Sum", label = "5xx" }],
            [".", "TargetResponseTime", ".", ".", { stat = "p95", label = "p95 latency" }]
          ]
          view    = "timeSeries"
          stacked = false
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ASG CPU / InService"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name, { stat = "Average" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name, { stat = "Average", yAxis = "right" }]
          ]
          view   = "timeSeries"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "MySQL primary CPU / status"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", var.mysql_primary_id, { stat = "Average" }],
            [".", "StatusCheckFailed", ".", ".", { stat = "Maximum", yAxis = "right" }]
          ]
          view   = "timeSeries"
          period = 60
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "App logs (request_id)"
          region = var.aws_region
          query  = "SOURCE '/${var.resource_prefix}/app' | fields @timestamp, request_id, message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}

output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }
output "dashboard_name" { value = aws_cloudwatch_dashboard.main.dashboard_name }
output "log_group_app" { value = aws_cloudwatch_log_group.app.name }

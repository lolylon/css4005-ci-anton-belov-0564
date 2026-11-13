variable "resource_prefix" { type = string }
variable "ami_id" { type = string }
variable "app_subnet_ids" { type = list(string) }
variable "availability_zones" { type = list(string) }
variable "sg_k3s_id" { type = string }
variable "instance_profile_name" { type = string }
variable "server_instance_type" { type = string }
variable "agent_instance_type" { type = string }
variable "agent_min" { type = number }
variable "agent_max" { type = number }
variable "agent_desired" { type = number }
variable "aws_region" { type = string }
variable "secret_k3s_token" { type = string }
variable "ecr_repository_url" { type = string }
variable "alert_cpu_pct" { type = number }

locals {
  server_ud = base64encode(templatefile("${path.module}/../../../scripts/k3s-server.sh", {
    resource_prefix    = var.resource_prefix
    aws_region         = var.aws_region
    secret_k3s_token   = var.secret_k3s_token
    ecr_repository_url = var.ecr_repository_url
  }))
  agent_ud = base64encode(templatefile("${path.module}/../../../scripts/k3s-agent.sh", {
    resource_prefix  = var.resource_prefix
    aws_region       = var.aws_region
    secret_k3s_token = var.secret_k3s_token
  }))
}

resource "aws_instance" "k3s_server" {
  ami                    = var.ami_id
  instance_type          = var.server_instance_type
  subnet_id              = var.app_subnet_ids[0]
  vpc_security_group_ids = [var.sg_k3s_id]
  iam_instance_profile   = var.instance_profile_name
  user_data_base64       = local.server_ud

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = "${var.resource_prefix}-k3s-server"
    Role = "k3s-server"
  }
}

resource "aws_launch_template" "k3s_agent" {
  name_prefix   = "${var.resource_prefix}-k3s-agent-"
  image_id      = var.ami_id
  instance_type = var.agent_instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.sg_k3s_id]
  user_data              = local.agent_ud

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.resource_prefix}-k3s-agent"
      Role = "k3s-agent"
    }
  }
}

resource "aws_autoscaling_group" "k3s_agent" {
  name                      = "${var.resource_prefix}-k3s-agents"
  min_size                  = var.agent_min
  max_size                  = var.agent_max
  desired_capacity          = var.agent_desired
  vpc_zone_identifier       = var.app_subnet_ids
  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.k3s_agent.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.resource_prefix}-k3s-agent"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = var.resource_prefix
    propagate_at_launch = true
  }
  tag {
    key                 = "Role"
    value               = "k3s-agent"
    propagate_at_launch = true
  }

  depends_on = [aws_instance.k3s_server]
}

# Spiky traffic → target tracking on ASG average CPU (near alert threshold)
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.resource_prefix}-k3s-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.k3s_agent.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    # Scale nodes before the 80% alarm; leave headroom under alert_cpu_pct
    target_value = max(50, var.alert_cpu_pct - 20)
  }
}

output "k3s_server_id" { value = aws_instance.k3s_server.id }
output "k3s_server_private_ip" { value = aws_instance.k3s_server.private_ip }
output "asg_name" { value = aws_autoscaling_group.k3s_agent.name }
output "launch_template_id" { value = aws_launch_template.k3s_agent.id }

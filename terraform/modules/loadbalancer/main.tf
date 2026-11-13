variable "resource_prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "sg_alb_id" { type = string }
variable "k3s_asg_name" { type = string }
variable "k3s_server_id" { type = string }

resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = "${var.resource_prefix}.local"
    organization = "CSS4005 Lab"
  }

  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
  dns_names             = ["${var.resource_prefix}.local", "localhost"]
}

resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem
}

resource "aws_lb" "app" {
  name               = "${var.resource_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.resource_prefix}-alb" }
}

resource "aws_lb_target_group" "http" {
  name     = "${var.resource_prefix}-tg-http"
  port     = 30080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/readyz"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = { Name = "${var.resource_prefix}-tg-http" }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Attach ASG agents + explicit server to target group
resource "aws_autoscaling_attachment" "agents" {
  autoscaling_group_name = var.k3s_asg_name
  lb_target_group_arn    = aws_lb_target_group.http.arn
}

resource "aws_lb_target_group_attachment" "server" {
  target_group_arn = aws_lb_target_group.http.arn
  target_id        = var.k3s_server_id
  port             = 30080
}

output "alb_dns_name" { value = aws_lb.app.dns_name }
output "alb_arn" { value = aws_lb.app.arn }
output "alb_zone_id" { value = aws_lb.app.zone_id }
output "target_group_arn" { value = aws_lb_target_group.http.arn }
output "certificate_arn" { value = aws_acm_certificate.alb.arn }

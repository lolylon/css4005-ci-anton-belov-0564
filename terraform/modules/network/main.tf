# 3-tier VPC across 2 AZs. Single NAT EC2 for cost (ADR-001).
# Subnet plan (from vpc_cidr 10.195.0.0/16):
#   public  : .0.0/24  .1.0/24
#   app     : .10.0/24 .11.0/24
#   db      : .20.0/24 .21.0/24

locals {
  az_a = var.availability_zones[0]
  az_b = var.availability_zones[1]
  # Build /24s under the /16: 10.195.X.0/24
  public_a_cidr = cidrsubnet(var.vpc_cidr, 8, 0)
  public_b_cidr = cidrsubnet(var.vpc_cidr, 8, 1)
  app_a_cidr    = cidrsubnet(var.vpc_cidr, 8, 10)
  app_b_cidr    = cidrsubnet(var.vpc_cidr, 8, 11)
  db_a_cidr     = cidrsubnet(var.vpc_cidr, 8, 20)
  db_b_cidr     = cidrsubnet(var.vpc_cidr, 8, 21)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.resource_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.resource_prefix}-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_a_cidr
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.resource_prefix}-public-a"
    Tier = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_b_cidr
  availability_zone       = local.az_b
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.resource_prefix}-public-b"
    Tier = "public"
  }
}

resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_a_cidr
  availability_zone = local.az_a
  tags = {
    Name = "${var.resource_prefix}-app-a"
    Tier = "app"
  }
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_b_cidr
  availability_zone = local.az_b
  tags = {
    Name = "${var.resource_prefix}-app-b"
    Tier = "app"
  }
}

resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.db_a_cidr
  availability_zone = local.az_a
  tags = {
    Name = "${var.resource_prefix}-db-a"
    Tier = "db"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.db_b_cidr
  availability_zone = local.az_b
  tags = {
    Name = "${var.resource_prefix}-db-b"
    Tier = "db"
  }
}

# --- Public route table ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.resource_prefix}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# --- Security groups (chaining by SG reference, not VPC CIDR) ---
resource "aws_security_group" "alb" {
  name        = "${var.resource_prefix}-sg-alb"
  description = "ALB: internet 80/443 only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.resource_prefix}-sg-alb" }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "nat" {
  name        = "${var.resource_prefix}-sg-nat"
  description = "NAT instance"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.resource_prefix}-sg-nat" }

  ingress {
    description = "Forward from private VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "k3s" {
  name        = "${var.resource_prefix}-sg-k3s"
  description = "k3s nodes: traffic from ALB only for NodePort/ingress"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.resource_prefix}-sg-k3s" }

  # Traefik / NodePort range used by k3s ingress
  ingress {
    description     = "HTTP NodePort from ALB"
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description     = "HTTPS NodePort from ALB"
    from_port       = 30443
    to_port         = 30443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  # Intra-cluster
  ingress {
    description = "k3s cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "${var.resource_prefix}-sg-db"
  description = "MySQL/ClickHouse: app tier only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.resource_prefix}-sg-db" }

  ingress {
    description     = "MySQL from k3s/app"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.k3s.id]
  }
  ingress {
    description     = "ClickHouse HTTP from k3s/app"
    from_port       = 8123
    to_port         = 8123
    protocol        = "tcp"
    security_groups = [aws_security_group.k3s.id]
  }
  ingress {
    description     = "ClickHouse native from k3s/app"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.k3s.id]
  }
  # Replication between DB hosts
  ingress {
    description = "MySQL replication / admin between DB nodes"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Optional SSH only from a fixed CIDR (documented bastion-alternative). Default: none.
resource "aws_security_group_rule" "ssh_optional" {
  count             = var.ssh_allowed_cidr != "" ? 1 : 0
  type              = "ingress"
  security_group_id = aws_security_group.k3s.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.ssh_allowed_cidr]
  description       = "SSH from operator IP only"
}

# --- NAT instance (cost ADR) ---
resource "aws_iam_role" "nat" {
  name = "${var.resource_prefix}-role-nat"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  name = "${var.resource_prefix}-profile-nat"
  role = aws_iam_role.nat.name
}

resource "aws_instance" "nat" {
  ami                         = var.nat_ami_id
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  iam_instance_profile        = aws_iam_instance_profile.nat.name
  associate_public_ip_address = true
  source_dest_check           = false

  # cloud-init: shebang at column 0. Use $ not $$ — Terraform only interpolates ${...};
  # $$ becomes literal $$ and bash treats $$ as PID (breaks $(...) ).
  user_data = <<-EOF
#!/bin/bash
set -eux
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-nat-forward.conf
sysctl -p /etc/sysctl.d/99-nat-forward.conf || true
PRIMARY_IF=$(ip -o -4 route show to default | awk '{print $5}')
iptables -t nat -C POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE
iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -C FORWARD -j ACCEPT 2>/dev/null || iptables -A FORWARD -j ACCEPT
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y iptables-persistent
netfilter-persistent save || true
EOF

  tags = {
    Name = "${var.resource_prefix}-nat"
    Role = "nat"
  }
}

resource "aws_eip" "nat" {
  domain   = "vpc"
  instance = aws_instance.nat.id
  tags     = { Name = "${var.resource_prefix}-nat-eip" }
}

# --- Private route tables (app + db) via NAT instance ---
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.resource_prefix}-rt-private-a" }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.resource_prefix}-rt-private-b" }
}

resource "aws_route" "private_a_nat" {
  route_table_id         = aws_route_table.private_a.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

resource "aws_route" "private_b_nat" {
  route_table_id         = aws_route_table.private_b.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.private_b.id
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.private_b.id
}

# --- NACL second layer on DB subnets ---
resource "aws_network_acl" "db" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]
  tags       = { Name = "${var.resource_prefix}-nacl-db" }

  # Allow MySQL/ClickHouse from app subnets only
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_a_cidr
    from_port  = 3306
    to_port    = 3306
  }
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_b_cidr
    from_port  = 3306
    to_port    = 3306
  }
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_a_cidr
    from_port  = 8123
    to_port    = 8123
  }
  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_b_cidr
    from_port  = 8123
    to_port    = 8123
  }
  ingress {
    rule_no    = 140
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_a_cidr
    from_port  = 9000
    to_port    = 9000
  }
  ingress {
    rule_no    = 150
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.app_b_cidr
    from_port  = 9000
    to_port    = 9000
  }
  # DB-to-DB replication within db subnets
  ingress {
    rule_no    = 160
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.db_a_cidr
    from_port  = 3306
    to_port    = 3306
  }
  ingress {
    rule_no    = 170
    protocol   = "tcp"
    action     = "allow"
    cidr_block = local.db_b_cidr
    from_port  = 3306
    to_port    = 3306
  }
  # Ephemeral return traffic
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

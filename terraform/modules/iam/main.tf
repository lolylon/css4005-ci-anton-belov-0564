variable "resource_prefix" { type = string }
variable "bucket_arn" { type = string }
variable "ecr_repository_arn" { type = string }
variable "secret_arns" { type = map(string) }
variable "aws_account_id" { type = string }
variable "aws_region" { type = string }
variable "github_org_repo" {
  type        = string
  description = "owner/repo for GitHub OIDC deploy role, e.g. anton-belov/css4005-final"
  default     = ""
}

# --- k3s / app node instance role ---
resource "aws_iam_role" "node" {
  name = "${var.resource_prefix}-role-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "node" {
  name = "${var.resource_prefix}-policy-node"
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadOwnSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = values(var.secret_arns)
      },
      {
        Sid    = "S3AppPrefix"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:AbortMultipartUpload"]
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/*"
        ]
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchAgent"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Sid    = "SsmBootstrapParams"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.resource_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.resource_prefix}-profile-node"
  role = aws_iam_role.node.name
}

# --- DB instance role (secrets + backup upload + SSM) ---
resource "aws_iam_role" "db" {
  name = "${var.resource_prefix}-role-db"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "db_ssm" {
  role       = aws_iam_role.db.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "db" {
  name = "${var.resource_prefix}-policy-db"
  role = aws_iam_role.db.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDbSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = values(var.secret_arns)
      },
      {
        Sid    = "UploadBackups"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListBucket"]
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/backups/*"
        ]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Sid    = "SsmBootstrapParams"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.resource_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "db" {
  name = "${var.resource_prefix}-profile-db"
  role = aws_iam_role.db.name
}

# --- GitHub Actions OIDC deploy role (optional until github_org_repo is set) ---
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.github_org_repo != "" ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "gha" {
  count = var.github_org_repo != "" ? 1 : 0
  name  = "${var.resource_prefix}-role-gha"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org_repo}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gha" {
  count = var.github_org_repo != "" ? 1 : 0
  name  = "${var.resource_prefix}-policy-gha"
  role  = aws_iam_role.gha[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = values(var.secret_arns)
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ec2:DescribeInstances",
          "elasticloadbalancing:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}

output "node_instance_profile_name" { value = aws_iam_instance_profile.node.name }
output "node_role_arn" { value = aws_iam_role.node.arn }
output "db_instance_profile_name" { value = aws_iam_instance_profile.db.name }
output "db_role_arn" { value = aws_iam_role.db.arn }
output "gha_role_arn" {
  value = try(aws_iam_role.gha[0].arn, "")
}

# Ideal least-privilege policy JSON for the report (even if LabRole forced elsewhere)
output "ideal_node_policy_json" {
  value = aws_iam_role_policy.node.policy
}

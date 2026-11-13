variable "resource_prefix" { type = string }
variable "backup_retention_days" { type = number }

resource "aws_s3_bucket" "app" {
  bucket = "${var.resource_prefix}-files"
  tags   = { Name = "${var.resource_prefix}-files" }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    id     = "expire-noncurrent-and-glacier"
    status = "Enabled"

    filter { prefix = "" }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 7
      storage_class   = "STANDARD_IA"
    }
  }

  rule {
    id     = "expire-old-logical-backups"
    status = "Enabled"

    filter { prefix = "backups/" }

    expiration {
      days = var.backup_retention_days
    }
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "${var.resource_prefix}-campus-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.resource_prefix}-campus-app" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

output "bucket_name" { value = aws_s3_bucket.app.id }
output "bucket_arn" { value = aws_s3_bucket.app.arn }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "ecr_repository_arn" { value = aws_ecr_repository.app.arn }

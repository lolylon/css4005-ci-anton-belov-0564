provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.resource_prefix
      ManagedBy   = "terraform"
      Course      = "CSS4005"
      Environment = var.environment
    }
  }
}

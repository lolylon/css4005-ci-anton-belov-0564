# Copy to backend.tf after creating the state bucket once (bootstrap).
# Never commit real state. Enable versioning + encryption + DynamoDB lock table.

terraform {
  backend "s3" {
    bucket         = "ci-anton-belov-0564-tfstate"
    key            = "final-project/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ci-anton-belov-0564-tf-locks"
    encrypt        = true
  }
}

# Remote State Backend Configuration (S3 + DynamoDB / Native S3 State Locking)
# Initialize with: terraform init -migrate-state

terraform {
  backend "s3" {
    bucket         = "marceleno-terraform-state-eu-west-3"
    key            = "multi-az-k3s/prod/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
    use_lockfile   = true
  }
}

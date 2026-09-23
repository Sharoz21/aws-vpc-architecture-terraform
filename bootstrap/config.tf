# bootstrap/main.tf
#
# Creates the S3 bucket + DynamoDB lock table used as the remote state
# backend for the root config (../main.tf).
#
# This config's own state MUST stay local. It creates the very bucket a
# remote backend would try to write into, so giving this config an S3
# backend would just recreate the same chicken-and-egg problem one level
# up. Run it once per environment (per MiniStack instance), then leave it
# alone — you should rarely need to touch it again.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "mock_access_key"
  region                      = "us-east-1"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "tf_state" {
  bucket        = "tf-test-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "tf-test-lock-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

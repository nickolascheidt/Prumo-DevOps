terraform {
  # `use_lockfile` (native S3 locking) needs 1.10. The alternative, a DynamoDB table, is
  # deprecated.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: the bucket, prumo-tfstate-<account-id>, is passed at init
  # (`-backend-config="bucket=..."`) by scripts/aws/bootstrap-dev.sh, which also creates
  # it. Keeps the account ID out of the repo.
  backend "s3" {
    key          = "aws/dev.tfstate"
    region       = "sa-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "prumo"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

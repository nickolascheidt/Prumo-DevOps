terraform {
  # `use_lockfile` (locking nativo do S3) exige 1.10. A alternativa, tabela
  # DynamoDB, está deprecada e será removida.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "prumo-tfstate-767397939785"
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

data "aws_caller_identity" "current" {}

locals {
  name         = "${var.project}-dev"
  account_id   = data.aws_caller_identity.current.account_id
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

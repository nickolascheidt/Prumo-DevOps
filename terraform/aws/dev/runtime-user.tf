# The price of Lightsail: with no instance profile, the host needs a credential on disk
# to talk to AWS. The defense is to give that credential as little power as possible,
# which is what this file does.
resource "aws_iam_user" "box" {
  name = "${local.name}-box"
}

data "aws_iam_policy_document" "box" {
  # Pull the images. Read-only, and only these two repositories.
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [aws_ecr_repository.api.arn, aws_ecr_repository.web.arn]
  }

  # The ECR login token does not accept a specific resource.
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "box" {
  name   = "runtime"
  user   = aws_iam_user.box.name
  policy = data.aws_iam_policy_document.box.json
}

# There is NO aws_iam_access_key here, on purpose: Terraform would store the secret key in
# plain text in the state file. It is created once, by hand:
#
#     aws iam create-access-key --user-name prumo-dev-box
#
# What a leak of that key gives an attacker, in full: pulling the container images. It
# cannot read secrets, create resources or touch the instance. Small and bounded — but not
# zero, as it would be with an EC2 instance profile. If that ever matters, it is the right
# reason to move to EC2.

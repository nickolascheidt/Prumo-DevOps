output "ecr_registry" {
  description = "ECR host, used by docker login and in the image names."
  value       = local.ecr_registry
}

output "github_deploy_role_arn" {
  description = "Goes into the AWS_DEPLOY_ROLE_ARN secret of the application repos."
  value       = aws_iam_role.github_deploy.arn
}

output "public_ip" {
  description = "The instance's static IP. Becomes the sslip.io name, and the A record target when DNS is not on Route 53."
  value       = aws_lightsail_static_ip.app.ip_address
}

output "sslip_domain" {
  description = "Host name when there is no domain of your own: the IP with dashes. Goes into DOMAIN in the host's .env."
  value       = "${replace(aws_lightsail_static_ip.app.ip_address, ".", "-")}.sslip.io"
}

output "ssh" {
  description = "How to get into the host. The user depends on the blueprint: ec2-user on Amazon Linux 2023, ubuntu on Ubuntu blueprints."
  value       = "ssh -i ~/.ssh/prumo-dev ec2-user@${aws_lightsail_static_ip.app.ip_address}"
}

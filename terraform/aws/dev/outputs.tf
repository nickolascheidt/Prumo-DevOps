output "ecr_registry" {
  description = "Host do ECR, usado no docker login e nos nomes de imagem."
  value       = local.ecr_registry
}

output "queue_url" {
  description = "Vai para Sqs__QueueUrl no .env da instância."
  value       = aws_sqs_queue.notifications.url
}

output "dead_letter_queue_url" {
  description = "Vai para Sqs__DeadLetterQueueUrl quando o worker existir."
  value       = aws_sqs_queue.notifications_dlq.url
}

output "github_deploy_role_arn" {
  description = "Vai para o secret AWS_DEPLOY_ROLE_ARN nos três repos."
  value       = aws_iam_role.github_deploy.arn
}

output "public_ip" {
  description = "IP estático da instância. Vira o nome sslip.io e o alvo do registro A se o DNS não estiver no Route 53."
  value       = aws_lightsail_static_ip.app.ip_address
}

output "sslip_domain" {
  description = "O nome de host do caminho sem domínio próprio: o IP com hífens. Vai para DOMAIN no .env da máquina."
  value       = "${replace(aws_lightsail_static_ip.app.ip_address, ".", "-")}.sslip.io"
}

output "ssh" {
  description = "Como entrar na máquina. O usuário depende do blueprint: ec2-user no Amazon Linux 2023, ubuntu nos blueprints Ubuntu."
  value       = "ssh -i ~/.ssh/prumo-dev ec2-user@${aws_lightsail_static_ip.app.ip_address}"
}

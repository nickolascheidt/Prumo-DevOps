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

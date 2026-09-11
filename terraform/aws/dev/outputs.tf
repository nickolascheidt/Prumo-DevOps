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

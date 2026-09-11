output "ecr_registry" {
  description = "Host do ECR, usado no docker login e nos nomes de imagem."
  value       = local.ecr_registry
}

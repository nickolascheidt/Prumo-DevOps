variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "container_app_environment_id" {
  type        = string
  description = "ID of the Container Apps environment the Redis sidecar runs in."
}

variable "image" {
  type    = string
  default = "redis:7-alpine"
}

variable "cpu" {
  type    = number
  default = 0.25
}

variable "memory" {
  type    = string
  default = "0.5Gi"
}

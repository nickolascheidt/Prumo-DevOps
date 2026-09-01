variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "container_app_environment_id" { type = string }
variable "acr_login_server" { type = string }
variable "identity_id" {
  type        = string
  description = "Resource ID of the user-assigned identity used for ACR pull and Key Vault access."
}
variable "image" {
  type        = string
  description = "Full image reference, e.g. acr.azurecr.io/saasbase-api:<sha>."
}
variable "target_port" { type = number }
variable "cpu" {
  type    = number
  default = 0.5
}
variable "memory" {
  type    = string
  default = "1Gi"
}
variable "min_replicas" {
  type        = number
  default     = 0
  description = <<-EOT
    0 lets the app scale to zero when idle, which is what keeps a parked environment near
    free -- Container Apps bills per replica-second. The cost is a cold start on the first
    request after idling. Set it to 1 for an environment that must answer instantly.
  EOT
}
variable "max_replicas" {
  type    = number
  default = 3
}

variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain (non-secret) environment variables."
}

variable "secret_env" {
  type        = map(string)
  default     = {}
  description = "Env var name => Key Vault versionless secret ID. Surfaced as Container App secrets."
}

variable "liveness_path" {
  type    = string
  default = ""
}
variable "readiness_path" {
  type    = string
  default = ""
}

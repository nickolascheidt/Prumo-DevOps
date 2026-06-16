variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }

variable "secrets" {
  type        = map(string)
  sensitive   = true
  description = "Secret name => value to store in the vault."
}

variable "reader_principal_ids" {
  type        = map(string)
  default     = {}
  description = "Static label => Object ID granted Key Vault Secrets User (the Container Apps' managed identities). Keys must be known at plan time; values may be computed at apply time."
}

variable "admin_principal_id" {
  type        = string
  description = "Object ID of the deploying identity (needs to write secrets)."
}

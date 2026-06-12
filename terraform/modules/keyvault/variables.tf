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
  type        = list(string)
  default     = []
  description = "Object IDs granted Key Vault Secrets User (the Container Apps' managed identities)."
}

variable "admin_principal_id" {
  type        = string
  description = "Object ID of the deploying identity (needs to write secrets)."
}

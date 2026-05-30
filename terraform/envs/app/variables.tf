variable "env" { type = string }
variable "location" {
  type    = string
  default = "brazilsouth"
}

variable "acr_resource_group" {
  type    = string
  default = "rg-saasbase-core"
}
variable "acr_name" {
  type    = string
  default = "acrsaasbasecore"
}

variable "api_image_tag" {
  type        = string
  default     = "latest"
  description = "Image tag (app repo commit SHA) for the API container."
}
variable "web_image_tag" {
  type        = string
  default     = "latest"
  description = "Image tag (app repo commit SHA) for the web container."
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}
variable "jwt_key" {
  type      = string
  sensitive = true
}
variable "jwt_issuer" {
  type    = string
  default = "SaaS_BasePlatformApi"
}
variable "jwt_audience" {
  type    = string
  default = "SaaS_BasePlatformClient"
}

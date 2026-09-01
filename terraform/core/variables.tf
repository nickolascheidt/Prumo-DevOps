variable "location" {
  type    = string
  default = "brazilsouth"
}

variable "acr_name" {
  type        = string
  default     = "acrsaasbasecore"
  description = "Globally-unique ACR name (alphanumeric)."
}

variable "acr_pusher_object_ids" {
  type        = list(string)
  default     = []
  description = "Service principal object IDs (backend + frontend GitHub identities) granted AcrPush."
}

variable "acr_sku" {
  type        = string
  default     = "Basic"
  description = <<-EOT
    ACR tier. Basic (10 GiB, ~1/4 the price of Standard) is ample for the two images this
    project pushes; Standard only buys storage and throughput we do not use. Bump it if the
    registry ever backs more than a couple of apps.
  EOT
}

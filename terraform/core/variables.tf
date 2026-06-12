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

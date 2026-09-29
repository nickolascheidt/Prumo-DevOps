variable "aws_region" {
  description = "Region for everything in this environment."
  type        = string
  default     = "sa-east-1"
}

variable "project" {
  description = "Prefix for resource names."
  type        = string
  default     = "prumo"
}

variable "domain" {
  description = "Full host name of this environment, e.g. app.example.com. Only used for the Route 53 record; without a domain of your own, leave it empty and use the sslip_domain output."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 zone ID. Empty means DNS is managed outside AWS (or not at all, with sslip.io) and no record is created."
  type        = string
  default     = ""
}

variable "bundle_id" {
  description = "Lightsail plan. small_3_0 is 2 GB, 2 vCPU, 60 GB SSD and a static IP for a fixed US$ 12/month. If it gets tight, medium_3_0 (4 GB, US$ 24)."
  type        = string
  default     = "small_3_0"
}

variable "blueprint_id" {
  description = "Lightsail base image. Check the exact id with `aws lightsail get-blueprints` before the first apply — AWS renames blueprints between releases."
  type        = string
  default     = "amazon_linux_2023"
}

variable "availability_zone" {
  description = "Lightsail AZ. Unlike EC2, Lightsail requires an explicit AZ at creation."
  type        = string
  default     = "sa-east-1a"
}

variable "ssh_allowed_cidr" {
  description = "Where SSH is accepted from, e.g. 189.10.20.30/32. bootstrap-dev.sh fills it with your current public IP. No default on purpose: Terraform asks instead of silently opening port 22 to the world."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Public half of the host's key pair. The `~` is expanded with pathexpand: `file()` alone does NOT expand it and would look for a directory named `~`."
  type        = string
  default     = "~/.ssh/prumo-dev.pub"
}

variable "github_repos" {
  description = "Repositories allowed to assume the deploy role through OIDC, as owner/repo."
  type        = list(string)
  default = [
    "nickolascheidt/Prumo",
    "nickolascheidt/Prumo-Angular",
    "nickolascheidt/Prumo-DevOps",
  ]
}

variable "aws_region" {
  description = "Região de tudo neste ambiente."
  type        = string
  default     = "sa-east-1"
}

variable "project" {
  description = "Prefixo dos nomes de recurso."
  type        = string
  default     = "prumo"
}

variable "domain" {
  description = "Domínio completo deste ambiente, ex.: dev.seudominio.com."
  type        = string
}

variable "route53_zone_id" {
  description = "Zone ID no Route 53. Vazio significa que o DNS é gerenciado fora da AWS e o registro A é criado à mão."
  type        = string
  default     = ""
}

variable "bundle_id" {
  description = "Plano do Lightsail. small_3_0 são 2 GB, 2 vCPU, 60 GB de SSD e IP estático por US$ 12/mês fixos. Se apertar, medium_3_0 (4 GB, US$ 24)."
  type        = string
  default     = "small_3_0"
}

variable "blueprint_id" {
  description = "Imagem base do Lightsail. Confirme o id exato com `aws lightsail get-blueprints` antes do primeiro apply — a AWS renomeia blueprints entre releases."
  type        = string
  default     = "amazon_linux_2023"
}

variable "availability_zone" {
  description = "AZ do Lightsail. Ao contrário da EC2, ele exige a AZ explícita na criação."
  type        = string
  default     = "sa-east-1a"
}

variable "github_repos" {
  description = "Repos que podem assumir a role de deploy por OIDC, no formato owner/repo."
  type        = list(string)
  default = [
    "nickolascheidt/SaaSBasePlatform",
    "nickolascheidt/SaaSBasePlatform-Angular",
    "nickolascheidt/SaaSBasePlatform-DevOps",
  ]
}

# A metade pública da chave gerada na Task 5, Passo 1. A privada nunca passa pelo
# Terraform e portanto nunca entra no state file.
#
# pathexpand(), e não file("~/...") direto: o file() NÃO expande o til — ele
# procuraria um diretório chamado "~" e falharia no apply.
resource "aws_lightsail_key_pair" "app" {
  name       = local.name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_lightsail_instance" "app" {
  name              = local.name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.app.name

  user_data = file("${path.module}/user-data.sh")

  # O backup inteiro, no lugar da role + policy de DLM da versão EC2. O Lightsail
  # guarda os 7 snapshots automáticos mais recentes e apaga o resto sozinho.
  # O horário é UTC e precisa ser hora cheia: 06:00 UTC = 03:00 em Brasília.
  # O atributo é `snapshot_time`. O plano dizia `snapshot_time_of_day`, que não
  # existe no provider — o `terraform validate` pegou.
  add_on {
    type          = "AutoSnapshot"
    snapshot_time = "06:00"
    status        = "Enabled"
  }

  tags = { Name = local.name }
}

# IP fixo: sem ele o endereço muda a cada recriação, e com ele mudam o nome
# sslip.io e o certificado do Caddy.
resource "aws_lightsail_static_ip" "app" {
  name = local.name
}

resource "aws_lightsail_static_ip_attachment" "app" {
  static_ip_name = aws_lightsail_static_ip.app.name
  instance_name  = aws_lightsail_instance.app.name
}

# O Lightsail abre 22 e 80 por padrão. Isto substitui a regra inteira: 80 e 443
# para todo mundo, 22 só do seu IP.
resource "aws_lightsail_instance_public_ports" "app" {
  instance_name = aws_lightsail_instance.app.name

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = [var.ssh_allowed_cidr]
  }
}

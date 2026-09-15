# Só existe quando o DNS está no Route 53. Com route53_zone_id vazio, este
# arquivo não gera recurso nenhum e o registro A é criado à mão no registrador —
# ou nem existe, no caminho do sslip.io, em que o nome já resolve sozinho.
#
# O alvo é o IP estático do Lightsail. O plano dizia `aws_eip.app.public_ip`,
# que é resíduo da versão EC2: não existe recurso aws_eip nesta árvore.
resource "aws_route53_record" "app" {
  count = var.route53_zone_id == "" ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_lightsail_static_ip.app.ip_address]
}

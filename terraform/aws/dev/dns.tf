# Only exists when DNS is on Route 53. With an empty route53_zone_id this file creates
# nothing, and the A record is created by hand at the registrar — or does not exist at
# all with sslip.io, where the name resolves by itself.
resource "aws_route53_record" "app" {
  count = var.route53_zone_id == "" ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_lightsail_static_ip.app.ip_address]
}

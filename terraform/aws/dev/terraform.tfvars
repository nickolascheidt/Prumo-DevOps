aws_region = "sa-east-1"

# With a domain of your own on Route 53, set both. Without one, leave them empty and use
# the sslip_domain output (the static IP with dashes, e.g. 54-207-1-2.sslip.io) as DOMAIN
# in the host's .env.
domain          = ""
route53_zone_id = ""

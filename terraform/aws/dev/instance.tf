# The public half of the host's key pair. The private half never goes through Terraform,
# so it never lands in the state file.
#
# pathexpand(), not file("~/...") directly: file() does NOT expand the tilde — it would
# look for a directory named "~" and fail at apply.
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

  # The whole backup story: Lightsail keeps the 7 most recent automatic snapshots and
  # deletes the rest by itself. The time is UTC and must be a whole hour:
  # 06:00 UTC = 03:00 in Brasília.
  add_on {
    type          = "AutoSnapshot"
    snapshot_time = "06:00"
    status        = "Enabled"
  }

  tags = { Name = local.name }
}

# A fixed IP: without it the address changes on every re-creation, and with it the
# sslip.io name and Caddy's certificate.
resource "aws_lightsail_static_ip" "app" {
  name = local.name
}

resource "aws_lightsail_static_ip_attachment" "app" {
  static_ip_name = aws_lightsail_static_ip.app.name
  instance_name  = aws_lightsail_instance.app.name
}

# Lightsail opens 22 and 80 by default. This replaces the whole rule set: 80 and 443 for
# everyone, 22 only from ssh_allowed_cidr.
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

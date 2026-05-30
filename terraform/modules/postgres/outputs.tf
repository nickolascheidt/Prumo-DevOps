output "connection_string" {
  value     = "Host=${azurerm_postgresql_flexible_server.this.fqdn};Port=5432;Database=${var.database_name};Username=${var.administrator_login};Password=${var.administrator_password};SslMode=Require;Trust Server Certificate=true"
  sensitive = true
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

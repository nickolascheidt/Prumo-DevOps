output "connection_string" {
  # Internal, non-TLS within the Container Apps environment. abortConnect=False so
  # the API tolerates the cache being briefly unavailable on startup.
  value     = "${azurerm_container_app.this.name}:6379,ssl=False,abortConnect=False"
  sensitive = true
}

output "vault_id" {
  value = azurerm_key_vault.this.id
}

output "secret_ids" {
  value = { for k, s in azurerm_key_vault_secret.this : k => s.versionless_id }
}

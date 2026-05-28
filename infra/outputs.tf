output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}

output "azure_dns_nameservers" {
  value = azurerm_dns_zone.main.name_servers
}

output "staging_url" {
  value = "https://staging.restauranty.${var.dns_zone_name}"
}

output "production_url" {
  value = "https://restauranty.${var.dns_zone_name}"
}

output "ingress_public_ip" {
  value = azurerm_public_ip.ingress.ip_address
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.aks_name

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name       = "agentpool"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }

  lifecycle {
    ignore_changes = [
      tags,
      default_node_pool[0].upgrade_settings,
      default_node_pool[0].node_count
    ]
  }
}

resource "azurerm_public_ip" "ingress" {
  name                = "pip-restauranty-ingress"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
}

data "azurerm_resources" "aks_nsg" {
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  type                = "Microsoft.Network/networkSecurityGroups"

  depends_on = [azurerm_kubernetes_cluster.aks]
}

locals {
  aks_nsg_name = data.azurerm_resources.aks_nsg.resources[0].name
}

resource "azurerm_network_security_rule" "allow_ingress_nodeports" {
  name                        = "Allow-Ingress-NodePorts"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["30000-32767"]
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_kubernetes_cluster.aks.node_resource_group
  network_security_group_name = local.aks_nsg_name
}

resource "azurerm_network_security_rule" "allow_http_https" {
  name                        = "Allow-HTTP-HTTPS"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_kubernetes_cluster.aks.node_resource_group
  network_security_group_name = local.aks_nsg_name
}

resource "kubernetes_namespace_v1" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "ingress_nginx" {
  depends_on = [
    kubernetes_namespace_v1.ingress_nginx,
    azurerm_public_ip.ingress,
    azurerm_network_security_rule.allow_ingress_nodeports,
    azurerm_network_security_rule.allow_http_https
  ]

  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"

  set {
    name  = "controller.service.loadBalancerIP"
    value = azurerm_public_ip.ingress.ip_address
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }
}

resource "helm_release" "cert_manager" {
  depends_on = [
    kubernetes_namespace_v1.cert_manager
  ]

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

resource "kubectl_manifest" "letsencrypt_production_clusterissuer" {
  depends_on = [
    helm_release.cert_manager
  ]

  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    email: ${var.letsencrypt_email}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-production-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
YAML

  lifecycle {
    ignore_changes = [
      yaml_incluster
    ]
  }
}

resource "azurerm_dns_a_record" "restauranty_production" {
  name                = "restauranty"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress.ip_address]
}

resource "azurerm_dns_a_record" "restauranty_staging" {
  name                = "staging.restauranty"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress.ip_address]
}

resource "azurerm_dns_a_record" "grafana" {
  name                = "grafana.restauranty"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress.ip_address]
}

resource "azurerm_dns_a_record" "alertmanager" {
  name                = "alertmanager.restauranty"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress.ip_address]
}

resource "azurerm_dns_a_record" "prometheus" {
  name                = "prometheus.restauranty"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress.ip_address]
}

resource "azurerm_dns_a_record" "loki" {
  name                = "loki.restauranty"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_public_ip.ingress.ip_address]
}

resource "azurerm_container_registry" "acr" {
  name                = "restaurantyacrfatemeh"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}
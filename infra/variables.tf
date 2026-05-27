variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "resource_group_name" {
  description = "Main resource group name."
  type        = string
  default     = "rg-restauranty"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "West Europe"
}

variable "aks_name" {
  description = "AKS cluster name."
  type        = string
  default     = "aks-restauranty"
}

variable "dns_zone_name" {
  description = "Azure DNS zone name. The domain must delegate nameservers to Azure DNS."
  type        = string
  default     = "codewithfatemeh.online"
}

variable "staging_hostname" {
  type    = string
  default = "staging.restauranty.codewithfatemeh.online"
}

variable "production_hostname" {
  type    = string
  default = "restauranty.codewithfatemeh.online"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "kubernetes_version" {
  type    = string
  default = null
}

variable "letsencrypt_email" {
  description = "Email used by cert-manager Let's Encrypt ClusterIssuer."
  type        = string
}

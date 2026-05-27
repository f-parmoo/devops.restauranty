# Restauranty Terraform Infrastructure

This Terraform setup creates:

- Azure Resource Group
- AKS cluster
- Azure DNS Zone
- A records for staging and production
- NGINX Ingress Controller via Helm
- cert-manager via Helm
- Let's Encrypt ClusterIssuer

## One manual step

Because the domain was purchased in Namecheap, the domain nameservers must point to Azure DNS nameservers.
After `terraform apply`, copy the `azure_dns_nameservers` output into Namecheap → Domain → Manage → Nameservers → Custom DNS.

## Usage

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

Then connect kubectl:

```bash
az aks get-credentials --resource-group rg-restauranty --name aks-restauranty --overwrite-existing
```

Deploy the app with Kustomize:

```bash
kubectl apply -k ../k8s/overlays/staging
kubectl apply -k ../k8s/overlays/production
```

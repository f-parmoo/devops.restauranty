# Security & Compliance

This document summarizes the security and compliance approach used in the Restauranty DevOps deployment project.

## 1. Security Overview

The Restauranty application is deployed as a microservices-based system on Azure Kubernetes Service (AKS).

The application contains:

* React client
* Auth microservice
* Items microservice
* Discounts microservice
* MongoDB database
* NGINX Ingress Controller
* TLS certificates managed by cert-manager and Let's Encrypt

The intended production traffic flow is:

```text
Internet
  ↓
NGINX Ingress Controller
  ↓
React Client
  ↓
Backend Microservices
  ↓
MongoDB
```

Only the Ingress Controller is exposed publicly. Internal services are accessed through Kubernetes services and are not directly exposed to the internet.

---

## 2. Secret Management

Sensitive values are not committed to the GitHub repository.

Secrets such as JWT secret values, Cloudinary credentials, and other private configuration values are stored using:

* GitHub Actions Secrets for CI/CD
* Kubernetes Secrets for runtime application configuration

The Kubernetes deployments consume sensitive values from Kubernetes Secrets instead of hardcoding them inside manifest files.

Example secret usage:

```yaml
env:
  - name: SECRET
    valueFrom:
      secretKeyRef:
        name: restauranty-secret
        key: SECRET
```

This approach keeps sensitive values outside the source code and separates configuration from application logic.

---

## 3. HTTPS and TLS

The application uses HTTPS through:

* NGINX Ingress Controller
* cert-manager
* Let's Encrypt production ClusterIssuer

Public application endpoints are configured with TLS certificates.

The goal is to ensure that traffic between users and the public application endpoint is encrypted in transit.

---

## 4. Network Security

The project includes Kubernetes NetworkPolicy manifests to define a zero-trust network model between application components.

The intended access model is:

```text
Ingress Controller → Client
Client → Backend services
Backend services → MongoDB
All pods → DNS only when needed
```

The policies are designed to:

* Deny all traffic by default
* Allow ingress traffic only from the Ingress Controller to the client
* Allow the client to communicate with backend microservices
* Allow backend microservices to communicate with MongoDB
* Allow DNS egress to CoreDNS in the kube-system namespace

Example DNS egress policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### Current AKS Limitation

The current AKS cluster was created without a network policy engine.

Current Terraform configuration:

```hcl
network_profile {
  network_plugin    = "kubenet"
  load_balancer_sku = "standard"
}
```

Because the current cluster has:

```text
Network policy engine: None
```

Kubernetes accepts the NetworkPolicy resources, but they are not enforced at runtime.

For a real production deployment, the AKS cluster should be created with a supported network policy engine enabled.

Recommended production configuration:

```hcl
network_profile {
  network_plugin    = "kubenet"
  network_policy    = "azure"
  load_balancer_sku = "standard"
}
```

---

## 5. Authentication and Authorization

The auth microservice is responsible for user authentication and JWT token generation.

Backend services that require protected access should validate JWT tokens from request headers before allowing access to protected resources.

JWT-based authentication helps separate authentication responsibility from the other business services.

---

## 6. Container and Image Security

Application components are containerized and deployed through Kubernetes.

Current container security practices include:

* Images are built through CI/CD
* Images are stored in Azure Container Registry
* AKS is granted pull access to ACR using Azure role assignment
* Application containers are not exposed directly to the public internet

Recommended future improvements:

* Run containers as non-root users
* Add Kubernetes securityContext to deployments
* Drop unnecessary Linux capabilities
* Enable read-only root filesystem where possible
* Add image scanning with tools such as Trivy
* Add dependency scanning for Node.js packages

---

## 7. Cloud and IAM Security

The infrastructure is provisioned using Terraform.

AKS uses a system-assigned managed identity.

Azure Container Registry access is granted through an Azure role assignment using the `AcrPull` role. This follows the least-privilege principle because the AKS cluster only receives permission to pull images from the registry.

---

## 8. Data Protection and Compliance

MongoDB stores application data.

For a production environment, the following compliance and data protection practices should be considered:

* Use authentication for MongoDB
* Store database credentials in Kubernetes Secrets
* Use encrypted storage for persistent volumes
* Avoid storing sensitive personal data unless required
* Limit access to database services
* Use TLS for public traffic
* Keep secrets out of Git history
* Follow GDPR principles when storing user-related data

Relevant GDPR-oriented practices include:

* Data minimization
* Purpose limitation
* Access restriction
* Secure storage
* Ability to delete user data if required

---

## 9. Public Exposure

The public entry point of the system is the NGINX Ingress Controller.

The following components should not be publicly exposed:

* Auth service
* Items service
* Discounts service
* MongoDB service
* Internal Kubernetes services

Only HTTP/HTTPS traffic should be allowed from the internet to the Ingress Controller.

---

## 10. Summary

The project implements several security-focused practices:

* Kubernetes Secrets for sensitive runtime configuration
* GitHub Secrets for CI/CD secrets
* HTTPS using cert-manager and Let's Encrypt
* Public access through a single Ingress Controller
* Internal services hidden behind Kubernetes networking
* NetworkPolicy manifests prepared for zero-trust pod communication
* Azure managed identity and ACR pull role assignment
* Security and compliance documentation

The main known limitation is that the current AKS cluster was created without a network policy engine. Therefore, NetworkPolicy resources are documented and committed, but they are not enforced in the current cluster. In a production cluster, AKS should be created with Azure or Calico network policy enabled.

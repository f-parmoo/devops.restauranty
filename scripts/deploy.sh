#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

BLUE='\033[1;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ---------------------------------------------------------
# Namespaces
# ---------------------------------------------------------

STAGING_NS="restauranty-staging"
PRODUCTION_NS="restauranty-production"

# ---------------------------------------------------------
# Docker / ACR Configuration
# ---------------------------------------------------------

ACR_NAME="restaurantyacrfatemeh"
DOCKER_REGISTRY="restaurantyacrfatemeh.azurecr.io"
DOCKER_IMAGE_PREFIX="restauranty"

IMAGE_AUTH="$DOCKER_REGISTRY/$DOCKER_IMAGE_PREFIX-auth"
IMAGE_ITEMS="$DOCKER_REGISTRY/$DOCKER_IMAGE_PREFIX-items"
IMAGE_DISCOUNTS="$DOCKER_REGISTRY/$DOCKER_IMAGE_PREFIX-discounts"
IMAGE_CLIENT="$DOCKER_REGISTRY/$DOCKER_IMAGE_PREFIX-client"

TAG=$(git rev-parse --short HEAD)

# ---------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------

print_section() {
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""
}

apply_secret() {
  local environment=$1
  local namespace=$2
  local secret_file="k8s/overlays/$environment/secret.yaml"

  if [ ! -f "$secret_file" ]; then
    echo -e "${RED}❌ Missing secret file: $secret_file${NC}"
    echo -e "${YELLOW}Create it locally before running deploy.sh${NC}"
    exit 1
  fi

  echo -e "${YELLOW}🔐 Applying secret for $environment...${NC}"

  kubectl apply -f "$secret_file" -n "$namespace"
}

wait_for_namespace() {
  local namespace=$1

  echo -e "${YELLOW}⏳ Waiting for deployments in namespace: $namespace${NC}"

  if ! kubectl wait \
    --for=condition=available deployment \
    --all \
    -n "$namespace" \
    --timeout=300s; then

    echo -e "${RED}❌ Some deployments in $namespace are not healthy${NC}"

    kubectl get pods -n "$namespace"

    echo -e "${RED}📄 Recent Events:${NC}"

    kubectl get events -n "$namespace" \
      --sort-by=.lastTimestamp | tail -30

    echo -e "${RED}📦 Failed Pod Logs:${NC}"

    for pod in $(kubectl get pods \
      -n "$namespace" \
      --field-selector=status.phase!=Running \
      -o jsonpath='{.items[*].metadata.name}'); do

      echo -e "${RED}---- Logs for $pod ----${NC}"

      kubectl logs "$pod" \
        -n "$namespace" \
        --all-containers \
        --tail=100 || true
    done

    exit 1
  fi

  echo -e "${GREEN}✅ All deployments in $namespace are healthy${NC}"
}

# ---------------------------------------------------------
# Terraform
# ---------------------------------------------------------

print_section "☁️ Running Terraform"

terraform -chdir=infra init -input=false
terraform -chdir=infra apply -auto-approve -input=false

RESOURCE_GROUP=$(terraform -chdir=infra output -raw resource_group_name)
AKS_NAME=$(terraform -chdir=infra output -raw aks_name)

# ---------------------------------------------------------
# ACR Login
# ---------------------------------------------------------

print_section "🔐 Logging in to ACR"

az acr login --name "$ACR_NAME"

# ---------------------------------------------------------
# AKS Credentials
# ---------------------------------------------------------

print_section "☸️ Connecting to AKS"

az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --overwrite-existing


# ---------------------------------------------------------
# Build & Push Docker Images
# ---------------------------------------------------------

print_section "🚀 Building and pushing Docker images"

# -------------------------
# Backend Images
# -------------------------

docker buildx build \
  --platform linux/amd64 \
  -t $IMAGE_AUTH:$TAG \
  -f backend/auth/Dockerfile \
  ./backend/auth \
  --push

docker buildx build \
  --platform linux/amd64 \
  -t $IMAGE_ITEMS:$TAG \
  -f backend/items/Dockerfile \
  ./backend/items \
  --push

docker buildx build \
  --platform linux/amd64 \
  -t $IMAGE_DISCOUNTS:$TAG \
  -f backend/discounts/Dockerfile \
  ./backend/discounts \
  --push

# -------------------------
# Client Images
# -------------------------

docker buildx build \
  --platform linux/amd64 \
  --build-arg REACT_APP_SERVER_URL=https://staging.restauranty.codewithfatemeh.online \
  -t $IMAGE_CLIENT:staging-$TAG \
  -f client/Dockerfile \
  ./client \
  --push

docker buildx build \
  --platform linux/amd64 \
  --build-arg REACT_APP_SERVER_URL=https://restauranty.codewithfatemeh.online \
  -t $IMAGE_CLIENT:prod-$TAG \
  -f client/Dockerfile \
  ./client \
  --push

# ---------------------------------------------------------
# Update Kustomize Image Tags
# ---------------------------------------------------------

print_section "🛠 Updating kustomize image tags"

# -------------------------
# Staging
# -------------------------

cd k8s/overlays/staging

kustomize edit set image $IMAGE_AUTH=$IMAGE_AUTH:$TAG
kustomize edit set image $IMAGE_ITEMS=$IMAGE_ITEMS:$TAG
kustomize edit set image $IMAGE_DISCOUNTS=$IMAGE_DISCOUNTS:$TAG
kustomize edit set image $IMAGE_CLIENT=$IMAGE_CLIENT:staging-$TAG

# -------------------------
# Production
# -------------------------

cd ../production

kustomize edit set image $IMAGE_AUTH=$IMAGE_AUTH:$TAG
kustomize edit set image $IMAGE_ITEMS=$IMAGE_ITEMS:$TAG
kustomize edit set image $IMAGE_DISCOUNTS=$IMAGE_DISCOUNTS:$TAG
kustomize edit set image $IMAGE_CLIENT=$IMAGE_CLIENT:prod-$TAG

cd ../../..

# ---------------------------------------------------------
# Deploy Staging
# ---------------------------------------------------------

print_section "🚢 Deploying staging environment"

apply_secret "staging" "$STAGING_NS"

kubectl apply -k k8s/overlays/staging

# ---------------------------------------------------------
# Deploy Production
# ---------------------------------------------------------

print_section "🚢 Deploying production environment"

apply_secret "production" "$PRODUCTION_NS"

kubectl apply -k k8s/overlays/production

# ---------------------------------------------------------
# Wait For Deployments
# ---------------------------------------------------------

print_section "⏳ Waiting for deployments"

wait_for_namespace "$STAGING_NS"
wait_for_namespace "$PRODUCTION_NS"

# ---------------------------------------------------------
# Success
# ---------------------------------------------------------

print_section "🎉 Deployment completed successfully"

echo -e "${GREEN}🔗 Staging URL:${NC} https://staging.restauranty.codewithfatemeh.online"

echo -e "${GREEN}🔗 Production URL:${NC} https://restauranty.codewithfatemeh.online"

echo -e "${GREEN}📊 Grafana URL:${NC} https://grafana.restauranty.codewithfatemeh.online"

echo -e "${GREEN}📈 Prometheus URL:${NC} https://prometheus.restauranty.codewithfatemeh.online"

echo -e "${GREEN}🚨 Alertmanager URL:${NC} https://alertmanager.restauranty.codewithfatemeh.online"

echo -e "${GREEN}🪵 Loki URL:${NC} https://loki.restauranty.codewithfatemeh.online"
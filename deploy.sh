#!/bin/bash
set -e

BLUE='\033[1;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

STAGING_NS="restauranty-staging"
PRODUCTION_NS="restauranty-production"

TAG=$(git rev-parse --short HEAD)

echo -e "${BLUE}🚀 Building and pushing Docker images...${NC}"

# -------------------------
# Backend Images
# -------------------------

docker buildx build \
  --platform linux/amd64 \
  -t fatemehparmoo/restauranty-auth:$TAG \
  -f backend/auth/Dockerfile \
  ./backend/auth \
  --push

docker buildx build \
  --platform linux/amd64 \
  -t fatemehparmoo/restauranty-items:$TAG \
  -f backend/items/Dockerfile \
  ./backend/items \
  --push

docker buildx build \
  --platform linux/amd64 \
  -t fatemehparmoo/restauranty-discounts:$TAG \
  -f backend/discounts/Dockerfile \
  ./backend/discounts \
  --push

# -------------------------
# Client Images
# -------------------------

docker buildx build \
  --platform linux/amd64 \
  --build-arg REACT_APP_SERVER_URL=https://staging.restauranty.codewithfatemeh.online \
  -t fatemehparmoo/restauranty-client:staging-$TAG \
  -f client/Dockerfile \
  ./client \
  --push

docker buildx build \
  --platform linux/amd64 \
  --build-arg REACT_APP_SERVER_URL=https://restauranty.codewithfatemeh.online \
  -t fatemehparmoo/restauranty-client:prod-$TAG \
  -f client/Dockerfile \
  ./client \
  --push

echo -e "${YELLOW}🛠 Updating kustomize image tags...${NC}"

# -------------------------
# Staging
# -------------------------

cd k8s/overlays/staging

kustomize edit set image fatemehparmoo/restauranty-auth=fatemehparmoo/restauranty-auth:$TAG
kustomize edit set image fatemehparmoo/restauranty-items=fatemehparmoo/restauranty-items:$TAG
kustomize edit set image fatemehparmoo/restauranty-discounts=fatemehparmoo/restauranty-discounts:$TAG
kustomize edit set image fatemehparmoo/restauranty-client=fatemehparmoo/restauranty-client:staging-$TAG

# -------------------------
# Production
# -------------------------

cd ../production

kustomize edit set image fatemehparmoo/restauranty-auth=fatemehparmoo/restauranty-auth:$TAG
kustomize edit set image fatemehparmoo/restauranty-items=fatemehparmoo/restauranty-items:$TAG
kustomize edit set image fatemehparmoo/restauranty-discounts=fatemehparmoo/restauranty-discounts:$TAG
kustomize edit set image fatemehparmoo/restauranty-client=fatemehparmoo/restauranty-client:prod-$TAG

cd ../../..

echo -e "${YELLOW}☁️ Running Terraform...${NC}"

cd infra

terraform init
terraform apply --auto-approve

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
AKS_NAME=$(terraform output -raw aks_name)

echo -e "${YELLOW}☸️ Connecting to AKS...${NC}"

az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --overwrite-existing

cd ..

echo -e "${YELLOW}🚢 Deploying staging environment...${NC}"

kubectl apply -k k8s/overlays/staging

echo -e "${YELLOW}🚢 Deploying production environment...${NC}"

kubectl apply -k k8s/overlays/production

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
    kubectl get events -n "$namespace" --sort-by=.lastTimestamp | tail -30

    echo -e "${RED}📦 Failed Pod Logs:${NC}"

    for pod in $(kubectl get pods -n "$namespace" --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}'); do
      echo -e "${RED}---- Logs for $pod ----${NC}"
      kubectl logs "$pod" -n "$namespace" --all-containers --tail=100 || true
    done

    exit 1
  fi

  echo -e "${GREEN}✅ All deployments in $namespace are healthy${NC}"
}

wait_for_namespace "$STAGING_NS"
wait_for_namespace "$PRODUCTION_NS"

echo -e "${GREEN}🎉 Deployment completed successfully${NC}"

echo -e "${GREEN}🔗 Staging URL: https://staging.restauranty.codewithfatemeh.online${NC}"

echo -e "${GREEN}🔗 Production URL: https://restauranty.codewithfatemeh.online${NC}"
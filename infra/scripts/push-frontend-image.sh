#!/bin/bash

# Script to build and push Frontend Docker image to ECR for ECS deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$INFRA_DIR/.." && pwd)"
FRONTEND_DIR="$(cd "$PROJECT_ROOT/frontend" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get environment (default to dev)
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-ap-southeast-1}"

echo -e "${BLUE}=== CIOT Frontend Docker Image Push ===${NC}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed${NC}"
    exit 1
fi

# Get ECR repository URL from Terraform output
cd "$INFRA_DIR"
echo -e "${YELLOW}Getting ECR repository URL...${NC}"
ECR_REPO_URL=$(tofu output -raw ecr_frontend_repository_url 2>/dev/null || terraform output -raw ecr_frontend_repository_url 2>/dev/null)

if [ -z "$ECR_REPO_URL" ]; then
    echo -e "${RED}✗ Could not get ECR repository URL. Make sure infrastructure is deployed.${NC}"
    echo "Run: cd $INFRA_DIR && tofu apply"
    exit 1
fi

echo -e "${GREEN}✓ ECR Repository: $ECR_REPO_URL${NC}"
echo ""

# Get ALB DNS name for API URL
ALB_DNS=$(tofu output -raw alb_dns_name 2>/dev/null || terraform output -raw alb_dns_name 2>/dev/null)
if [ -z "$ALB_DNS" ]; then
    echo -e "${YELLOW}⚠ Could not get ALB DNS. API URL will not be set during build.${NC}"
    API_URL=""
else
    API_URL="http://${ALB_DNS}"
    echo -e "${GREEN}✓ API URL: $API_URL${NC}"
fi
echo ""

# Login to ECR
echo -e "${YELLOW}Logging in to ECR...${NC}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO_URL"
echo -e "${GREEN}✓ Logged in to ECR${NC}"
echo ""

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
echo "Looking for Dockerfile in frontend directory: $FRONTEND_DIR"
echo ""

# Check if frontend Dockerfile exists
if [ ! -f "$FRONTEND_DIR/dockerfile" ]; then
    echo -e "${YELLOW}⚠ Dockerfile not found at $FRONTEND_DIR/dockerfile${NC}"
    echo "Please ensure your frontend Dockerfile exists."
    exit 1
fi

# Generate tags
TIMESTAMP_TAG=$(date +%Y%m%d-%H%M%S)
GIT_SHA_TAG=""
if command -v git &> /dev/null && [ -d "$PROJECT_ROOT/.git" ]; then
    cd "$PROJECT_ROOT"
    GIT_SHA_TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "")
fi

# Build image with API URL as build arg
IMAGE_TAG="latest"
if [ -n "$API_URL" ]; then
    docker build --platform linux/amd64 \
        --build-arg REACT_APP_API_URL="$API_URL" \
        -f "$FRONTEND_DIR/dockerfile" \
        -t "$ECR_REPO_URL:$IMAGE_TAG" \
        "$FRONTEND_DIR"
else
    docker build --platform linux/amd64 \
        -f "$FRONTEND_DIR/dockerfile" \
        -t "$ECR_REPO_URL:$IMAGE_TAG" \
        "$FRONTEND_DIR"
fi
echo -e "${GREEN}✓ Docker image built${NC}"
echo ""

# Tag image with multiple tags
echo -e "${YELLOW}Tagging image...${NC}"
docker tag "$ECR_REPO_URL:$IMAGE_TAG" "$ECR_REPO_URL:latest"
docker tag "$ECR_REPO_URL:$IMAGE_TAG" "$ECR_REPO_URL:$TIMESTAMP_TAG"
if [ -n "$GIT_SHA_TAG" ]; then
    docker tag "$ECR_REPO_URL:$IMAGE_TAG" "$ECR_REPO_URL:$GIT_SHA_TAG"
    echo -e "${GREEN}✓ Image tagged: latest, $TIMESTAMP_TAG, $GIT_SHA_TAG${NC}"
else
    echo -e "${GREEN}✓ Image tagged: latest, $TIMESTAMP_TAG${NC}"
    echo -e "${YELLOW}⚠ Git SHA tag not available (not in git repo or git not installed)${NC}"
fi
echo ""

# Push all tags
echo -e "${YELLOW}Pushing images to ECR...${NC}"
docker push "$ECR_REPO_URL:latest"
docker push "$ECR_REPO_URL:$TIMESTAMP_TAG"
if [ -n "$GIT_SHA_TAG" ]; then
    docker push "$ECR_REPO_URL:$GIT_SHA_TAG"
fi
echo -e "${GREEN}✓ Images pushed to ECR${NC}"
echo ""

# Force ECS service update
echo -e "${YELLOW}Updating ECS service to use new image...${NC}"
CLUSTER_NAME="ciot-cluster-${ENVIRONMENT}"
SERVICE_NAME="ciot-frontend-service-${ENVIRONMENT}"

aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --force-new-deployment \
    --region "$REGION" > /dev/null

echo -e "${GREEN}✓ ECS service update initiated${NC}"
echo ""
echo -e "${BLUE}=== Deployment Complete ===${NC}"
echo ""
echo "Your frontend service is being updated with the new Docker image."
echo ""
echo "Image tags pushed:"
echo "  - latest"
echo "  - $TIMESTAMP_TAG"
if [ -n "$GIT_SHA_TAG" ]; then
    echo "  - $GIT_SHA_TAG"
fi
echo ""
echo "Check status with:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION"
echo ""


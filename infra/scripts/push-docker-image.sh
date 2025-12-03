#!/bin/bash

# Script to build and push Docker image to ECR for ECS deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$INFRA_DIR/.." && pwd)"
BACKEND_DIR="$(cd "$PROJECT_ROOT/backend" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get environment (default to dev)
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-ap-southeast-1}"

echo -e "${BLUE}=== CIOT Backend Docker Image Push ===${NC}"
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
ECR_REPO_URL=$(tofu output -raw ecr_repository_url 2>/dev/null || terraform output -raw ecr_repository_url 2>/dev/null)

if [ -z "$ECR_REPO_URL" ]; then
    echo -e "${RED}✗ Could not get ECR repository URL. Make sure infrastructure is deployed.${NC}"
    echo "Run: cd $INFRA_DIR && tofu apply"
    exit 1
fi

echo -e "${GREEN}✓ ECR Repository: $ECR_REPO_URL${NC}"
echo ""

# Login to ECR
echo -e "${YELLOW}Logging in to ECR...${NC}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO_URL"
echo -e "${GREEN}✓ Logged in to ECR${NC}"
echo ""

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
echo "Looking for Dockerfile in backend directory: $BACKEND_DIR"
echo ""

# Check if backend Dockerfile exists
if [ ! -f "$BACKEND_DIR/dockerfile" ]; then
    echo -e "${YELLOW}⚠ Dockerfile not found at $BACKEND_DIR/dockerfile${NC}"
    echo "Please ensure your backend Dockerfile exists and is named 'dockerfile'."
    echo ""
    echo "Example Dockerfile structure:"
    echo "  FROM python:3.11-slim"
    echo "  WORKDIR /app"
    echo "  COPY requirements.txt ."
    echo "  RUN pip install -r requirements.txt"
    echo "  COPY . ."
    echo "  EXPOSE 8080"
    echo "  CMD [\"python\", \"app.py\"]"
    echo ""
    read -p "Continue anyway? (y/N): " CONTINUE
    if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        exit 1
    fi
fi

# Build image (always from backend directory, using backend/dockerfile)
IMAGE_TAG="latest"
docker build --platform linux/amd64 -f "$BACKEND_DIR/dockerfile" -t "$ECR_REPO_URL:$IMAGE_TAG" "$BACKEND_DIR"
echo -e "${GREEN}✓ Docker image built${NC}"
echo ""

# Tag image
echo -e "${YELLOW}Tagging image...${NC}"
docker tag "$ECR_REPO_URL:$IMAGE_TAG" "$ECR_REPO_URL:$IMAGE_TAG"
echo -e "${GREEN}✓ Image tagged${NC}"
echo ""

# Push image
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push "$ECR_REPO_URL:$IMAGE_TAG"
echo -e "${GREEN}✓ Image pushed to ECR${NC}"
echo ""

# Force ECS service update
echo -e "${YELLOW}Updating ECS service to use new image...${NC}"
CLUSTER_NAME="ciot-cluster-${ENVIRONMENT}"
SERVICE_NAME="ciot-backend-service-${ENVIRONMENT}"

aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --force-new-deployment \
    --region "$REGION" > /dev/null

echo -e "${GREEN}✓ ECS service update initiated${NC}"
echo ""
echo -e "${BLUE}=== Deployment Complete ===${NC}"
echo ""
echo "Your backend service is being updated with the new Docker image."
echo "Check status with:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION"
echo ""


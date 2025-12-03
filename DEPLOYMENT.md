# CIOT Oil Detection Project - Deployment Guide

Complete guide for deploying the CIOT oil detection backend and frontend to AWS ECR and ECS.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Deployment](#quick-deployment)
3. [Detailed Workflow](#detailed-workflow)
4. [Backend Deployment](#backend-deployment)
5. [Frontend Deployment](#frontend-deployment)
6. [Deployment Methods](#deployment-methods)
7. [Rollback Procedures](#rollback-procedures)
8. [Troubleshooting](#troubleshooting)
9. [CI/CD Integration](#cicd-integration)

---

## Prerequisites

### Required Tools

- **AWS CLI** (v2.x recommended)

  ```bash
  aws --version
  ```

- **Docker** (v20.x or higher)

  ```bash
  docker --version
  ```

- **Terraform/OpenTofu** (infrastructure already applied)

  ```bash
  cd infra && tofu output
  ```

- **Node.js** (v18+ for frontend builds)
  ```bash
  node --version
  ```

### AWS Permissions Required

Your IAM user/role needs the following permissions:

- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:GetDownloadUrlForLayer`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`
- `ecr:DescribeImages`
- `ecr:ListImages`
- `ecs:RegisterTaskDefinition`
- `ecs:UpdateService`
- `ecs:DescribeServices`
- `ecs:DescribeTaskDefinition`
- `logs:CreateLogStream`
- `logs:PutLogEvents`

### AWS Configuration

Ensure your AWS credentials are configured:

```bash
aws configure list
# or
cat ~/.aws/credentials
```

Set the correct region (default: ap-southeast-1):

```bash
export AWS_REGION=ap-southeast-1
export ENVIRONMENT=dev  # or prod, staging, etc.
```

---

## Quick Deployment

### One-Command Deployment

From the project root:

```bash
# Deploy backend
cd infra
make push-backend

# Deploy frontend
make push-frontend
```

Or use the scripts directly:

```bash
# Backend
cd infra
./scripts/push-docker-image.sh

# Frontend
./scripts/push-frontend-image.sh
```

### View Available Commands

```bash
cd infra
make help
```

---

## Detailed Workflow

### Infrastructure Setup (First Time Only)

1. **Create RDS credentials secret:**

   ```bash
   cd infra
   make setup-secrets
   ```

2. **Apply infrastructure:**

   ```bash
   make apply
   ```

3. **Get important URLs:**
   ```bash
   make output-summary
   ```

---

## Backend Deployment

### Step 1: Build the Docker Image

```bash
cd backend
docker build -f dockerfile -t ciot-backend:latest .
```

**What happens:**

- Uses Python 3.11-slim base image
- Installs dependencies from `requirements.txt`
- Copies application code (`app.py`, `db_setup.py`)
- Exposes port 8080
- Sets up database schema and starts FastAPI server

**Build time:** ~2-5 minutes (first build), ~30 seconds (cached)

### Step 2: Authenticate with ECR

The push script handles this automatically, or manually:

```bash
cd infra
ECR_URI=$(tofu output -raw ecr_repository_url)
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI
```

**Authentication validity:** 12 hours

### Step 3: Tag the Image

```bash
ECR_URI=$(cd infra && tofu output -raw ecr_repository_url)
docker tag ciot-backend:latest ${ECR_URI}:latest
docker tag ciot-backend:latest ${ECR_URI}:$(date +%Y%m%d-%H%M%S)
docker tag ciot-backend:latest ${ECR_URI}:$(git rev-parse --short HEAD)
```

**Tags created:**

- `latest` - Always points to most recent
- `20241203-143022` - Timestamp for rollback
- `a3f2c1d` - Git commit SHA for tracking

### Step 4: Push to ECR

```bash
docker push ${ECR_URI}:latest
docker push ${ECR_URI}:$(date +%Y%m%d-%H%M%S)
docker push ${ECR_URI}:$(git rev-parse --short HEAD)
```

**Upload time:**

- First push: ~5-10 minutes (depends on connection)
- Subsequent pushes: ~1-3 minutes (only changed layers)

**Image size:** ~300-500 MB (compressed layers)

### Step 5: Update ECS Service

The push script does this automatically, or manually:

```bash
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-backend-service-dev \
  --force-new-deployment \
  --region ap-southeast-1
```

**Deployment time:** ~3-5 minutes

**What happens:**

1. ECS creates new task with updated image
2. New task starts and passes health checks (`/health` endpoint)
3. Old task is gracefully stopped
4. Service reaches stable state

### Step 6: Verify Backend Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster ciot-cluster-dev \
  --services ciot-backend-service-dev \
  --region ap-southeast-1 \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# View recent logs
aws logs tail /ecs/ciot-backend-dev --follow --region ap-southeast-1

# Test health endpoint
ALB_DNS=$(cd infra && tofu output -raw alb_dns_name)
curl http://${ALB_DNS}/health
```

---

## Frontend Deployment

### Step 1: Build the Docker Image

The frontend uses a multi-stage build:

```bash
cd frontend
docker build -f dockerfile -t ciot-frontend:latest .
```

**What happens:**

- Stage 1: Node.js builder - installs dependencies and builds React app
- Stage 2: Nginx - serves static files from build
- Sets `REACT_APP_API_URL` to ALB DNS name
- Exposes port 80

**Build time:** ~5-10 minutes (first build), ~2-3 minutes (cached)

### Step 2: Authenticate with ECR

```bash
cd infra
ECR_URI=$(tofu output -raw ecr_frontend_repository_url)
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI
```

### Step 3: Tag and Push Frontend Image

```bash
ECR_URI=$(cd infra && tofu output -raw ecr_frontend_repository_url)
ALB_DNS=$(cd infra && tofu output -raw alb_dns_name)

docker build \
  --build-arg REACT_APP_API_URL="http://${ALB_DNS}" \
  -f dockerfile \
  -t ciot-frontend:latest \
  .

docker tag ciot-frontend:latest ${ECR_URI}:latest
docker push ${ECR_URI}:latest
```

### Step 4: Update Frontend ECS Service

```bash
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-frontend-service-dev \
  --force-new-deployment \
  --region ap-southeast-1
```

### Step 5: Verify Frontend Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster ciot-cluster-dev \
  --services ciot-frontend-service-dev \
  --region ap-southeast-1 \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# View logs
aws logs tail /ecs/ciot-frontend-dev --follow --region ap-southeast-1

# Test frontend URL
FRONTEND_URL=$(cd infra && tofu output -raw frontend_url)
curl http://${FRONTEND_URL}/
```

---

## Deployment Methods

### Method 1: Make Commands (Recommended)

Simplest approach using the Makefile:

```bash
cd infra

# Deploy backend
make push-backend

# Deploy frontend
make push-frontend

# View infrastructure outputs
make output-summary
```

### Method 2: Deployment Scripts

Using the automated bash scripts:

**Backend:**

```bash
cd infra/scripts
./push-docker-image.sh
```

**Frontend:**

```bash
cd infra/scripts
./push-frontend-image.sh
```

Features:

- ✅ Colored output for readability
- ✅ Error checking at each step
- ✅ Automatic ECR login
- ✅ Automatic ECS service update
- ✅ Gets ECR URL from Terraform outputs

### Method 3: Manual Commands

Complete control with individual commands:

**Backend:**

```bash
# 1. Get ECR URL
cd infra
ECR_URI=$(tofu output -raw ecr_repository_url)

# 2. Login
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI

# 3. Build
cd ../backend
docker build -f dockerfile -t ciot-backend:latest .

# 4. Tag
docker tag ciot-backend:latest ${ECR_URI}:latest

# 5. Push
docker push ${ECR_URI}:latest

# 6. Update service
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-backend-service-dev \
  --force-new-deployment \
  --region ap-southeast-1
```

**Frontend:**

```bash
# 1. Get URLs
cd infra
ECR_URI=$(tofu output -raw ecr_frontend_repository_url)
ALB_DNS=$(tofu output -raw alb_dns_name)

# 2. Login
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI

# 3. Build with API URL
cd ../frontend
docker build \
  --build-arg REACT_APP_API_URL="http://${ALB_DNS}" \
  -f dockerfile \
  -t ciot-frontend:latest \
  .

# 4. Tag and push
docker tag ciot-frontend:latest ${ECR_URI}:latest
docker push ${ECR_URI}:latest

# 5. Update service
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-frontend-service-dev \
  --force-new-deployment \
  --region ap-southeast-1
```

---

## Rollback Procedures

### Quick Rollback to Previous Version

**Backend:**

```bash
# List recent images with timestamps
aws ecr describe-images \
  --repository-name ciot-backend-dev \
  --region ap-southeast-1 \
  --query 'sort_by(imageDetails,&imagePushedAt)[-10:].{Tag:imageTags[0],Pushed:imagePushedAt}' \
  --output table

# Update task definition to use specific image
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-backend-service-dev \
  --task-definition ciot-backend-dev:REVISION \
  --force-new-deployment \
  --region ap-southeast-1
```

**Frontend:**

```bash
# List recent frontend images
aws ecr describe-images \
  --repository-name ciot-frontend-dev \
  --region ap-southeast-1 \
  --query 'sort_by(imageDetails,&imagePushedAt)[-10:].{Tag:imageTags[0],Pushed:imagePushedAt}' \
  --output table

# Rollback frontend service
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-frontend-service-dev \
  --task-definition ciot-frontend-dev:REVISION \
  --force-new-deployment \
  --region ap-southeast-1
```

### Rollback Using Previous Task Definition

```bash
# List recent task definitions
aws ecs list-task-definitions \
  --family-prefix ciot-backend-dev \
  --sort DESC \
  --max-items 10 \
  --region ap-southeast-1

# Update service to specific task definition revision
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-backend-service-dev \
  --task-definition ciot-backend-dev:5 \
  --region ap-southeast-1
```

### Emergency Rollback

If the service is failing:

```bash
# Scale down to 0
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-backend-service-dev \
  --desired-count 0 \
  --region ap-southeast-1

# Deploy known good version (manually push old image or use previous task definition)
# Then scale back up
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-backend-service-dev \
  --desired-count 1 \
  --region ap-southeast-1
```

---

## Troubleshooting

### Issue: "no basic auth credentials"

**Cause:** Docker not authenticated with ECR

**Solution:**

```bash
cd infra
ECR_URI=$(tofu output -raw ecr_repository_url)
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI
```

### Issue: "repository does not exist"

**Cause:** ECR repository not created yet

**Solution:**

```bash
cd infra
tofu apply -target=aws_ecr_repository.backend
tofu apply -target=aws_ecr_repository.frontend
```

### Issue: Build fails with "cannot find requirements.txt"

**Cause:** Running build from wrong directory

**Solution:**

```bash
cd backend
docker build -f dockerfile -t ciot-backend:latest .
```

### Issue: Frontend build fails - "REACT_APP_API_URL not set"

**Cause:** Build arg missing during Docker build

**Solution:**

```bash
cd infra
ALB_DNS=$(tofu output -raw alb_dns_name)
cd ../frontend
docker build \
  --build-arg REACT_APP_API_URL="http://${ALB_DNS}" \
  -f dockerfile \
  -t ciot-frontend:latest \
  .
```

### Issue: ECS task fails to start

**Debugging steps:**

```bash
# 1. Check service events
aws ecs describe-services \
  --cluster ciot-cluster-dev \
  --services ciot-backend-service-dev \
  --region ap-southeast-1 \
  --query 'services[0].events[0:5]'

# 2. Check task logs
aws logs tail /ecs/ciot-backend-dev --follow --region ap-southeast-1

# 3. Verify task definition
aws ecs describe-task-definition \
  --task-definition ciot-backend-dev \
  --region ap-southeast-1

# 4. Check health check
# Container health check uses: curl -f http://localhost:8080/health
# Make sure curl is installed in Docker image (it is in dockerfile)
```

### Issue: "Task failed container health checks"

**Causes:**

- Health check endpoint not responding
- Container taking too long to start
- Memory/CPU limits too low

**Solutions:**

```bash
# Check logs for startup errors
aws logs tail /ecs/ciot-backend-dev --follow --region ap-southeast-1

# Verify health endpoint works locally
cd backend
docker-compose up
curl http://localhost:8080/health

# Check task resource allocation
aws ecs describe-task-definition \
  --task-definition ciot-backend-dev \
  --region ap-southeast-1 \
  --query 'taskDefinition.{CPU:cpu,Memory:memory}'
```

### Issue: "ResourceInitializationError: failed to validate logger args"

**Cause:** IAM role lacks CloudWatch Logs permissions

**Solution:**

```bash
cd infra
# Verify IAM policy includes frontend log group
tofu plan -target=aws_iam_role_policy.ecs_execution_role_policy
tofu apply -target=aws_iam_role_policy.ecs_execution_role_policy
```

### Issue: Frontend shows CORS errors

**Cause:** Backend CORS middleware not configured for frontend URL

**Solution:**
Update `backend/app.py` to include frontend ALB URL in CORS origins, or use the ALB path-based routing (already configured).

### Issue: Frontend can't reach backend API

**Cause:** `REACT_APP_API_URL` not set correctly during build

**Solution:**

```bash
# Rebuild frontend with correct API URL
cd infra
ALB_DNS=$(tofu output -raw alb_dns_name)
cd ../frontend
docker build \
  --build-arg REACT_APP_API_URL="http://${ALB_DNS}" \
  -f dockerfile \
  -t ciot-frontend:latest \
  .
# Then push and redeploy
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy CIOT Services

on:
  push:
    branches: [main]
    paths:
      - "backend/**"
      - "frontend/**"

jobs:
  deploy-backend:
    runs-on: ubuntu-latest
    if: contains(github.event.head_commit.modified, 'backend/')

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-southeast-1

      - name: Deploy Backend
        run: |
          cd infra
          make push-backend

  deploy-frontend:
    runs-on: ubuntu-latest
    if: contains(github.event.head_commit.modified, 'frontend/')

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-southeast-1

      - name: Deploy Frontend
        run: |
          cd infra
          make push-frontend
```

### GitLab CI Example

```yaml
stages:
  - deploy

deploy-backend:
  stage: deploy
  image: docker:latest
  services:
    - docker:dind
  before_script:
    - apk add --no-cache aws-cli
    - cd infra
    - ECR_URI=$(tofu output -raw ecr_repository_url)
    - aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin $ECR_URI
  script:
    - cd infra
    - make push-backend
  only:
    - main
  when: manual

deploy-frontend:
  stage: deploy
  image: docker:latest
  services:
    - docker:dind
  before_script:
    - apk add --no-cache aws-cli
    - cd infra
    - ECR_URI=$(tofu output -raw ecr_frontend_repository_url)
    - aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin $ECR_URI
  script:
    - cd infra
    - make push-frontend
  only:
    - main
  when: manual
```

---

## Best Practices

### 1. Always Tag Images Properly

```bash
# ✅ Good - Multiple tags for flexibility
docker tag app:latest ${ECR_URI}:latest
docker tag app:latest ${ECR_URI}:v1.2.3
docker tag app:latest ${ECR_URI}:$(git rev-parse --short HEAD)
docker tag app:latest ${ECR_URI}:$(date +%Y%m%d-%H%M%S)

# ❌ Bad - Only latest
docker tag app:latest ${ECR_URI}:latest
```

### 2. Test Locally Before Pushing

**Backend:**

```bash
cd backend
docker-compose up
curl http://localhost:8080/health
curl http://localhost:8080/readings-latest?limit=1
```

**Frontend:**

```bash
cd frontend
npm install
REACT_APP_API_URL=http://localhost:8080 npm start
# Test in browser at http://localhost:3000
```

### 3. Monitor Deployments

```bash
# Watch deployment progress
watch -n 5 'aws ecs describe-services \
  --cluster ciot-cluster-dev \
  --services ciot-backend-service-dev \
  --region ap-southeast-1 \
  --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount}"'

# Or use the wait command
aws ecs wait services-stable \
  --cluster ciot-cluster-dev \
  --services ciot-backend-service-dev \
  --region ap-southeast-1
```

### 4. Keep Images Small

- ✅ Use multi-stage builds (frontend already uses this)
- ✅ Use `.dockerignore` files
- ✅ Remove unnecessary dependencies
- ✅ Combine RUN commands

### 5. Secure Your Images

- ✅ Don't hardcode secrets in Dockerfile
- ✅ Use AWS Secrets Manager for RDS credentials
- ✅ Keep base images updated
- ✅ Scan images for vulnerabilities (ECR scanning enabled)

### 6. Deployment Order

When deploying both services:

1. **Deploy backend first** (frontend depends on backend API)
2. **Wait for backend to stabilize**
3. **Deploy frontend** (with correct API URL)

```bash
# Deploy in correct order
cd infra
make push-backend
sleep 60  # Wait for backend to stabilize
make push-frontend
```

---

## Deployment Checklist

Before deploying to production:

- [ ] Code reviewed and approved
- [ ] Tests passing locally
- [ ] Environment variables configured in Secrets Manager
- [ ] Database migrations prepared (if needed)
- [ ] Docker images build successfully
- [ ] Images scanned for vulnerabilities
- [ ] Backend health check passes locally
- [ ] Frontend builds with correct API URL
- [ ] Rollback plan prepared
- [ ] Monitoring/alerting configured
- [ ] Team notified of deployment

---

## Key URLs and Resources

After deployment, get important URLs:

```bash
cd infra
make output-summary
```

This will show:

- **Frontend URL** - Access your React application
- **Backend API URL** - FastAPI endpoints
- **ECS Cluster Name** - For service management
- **ALB DNS Name** - Load balancer endpoint

---

## Additional Resources

- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [React Documentation](https://react.dev/)

---

**Last Updated:** December 2025

**Project:** CIOT Oil Detection System

**Maintained By:** CIOT Development Team

# 50.046 Cloud Computing & IoT Project - Quick Start Guide

Complete guide for deploying and managing the IoT oil detection system.

## 📋 Table of Contents

1. [Project Overview](#-project-overview)
2. [Prerequisites](#-prerequisites)
3. [Infrastructure Setup](#️-infrastructure-setup)
4. [Quick Deployment](#quick-deployment)
5. [Health Checks](#-health-checks)
6. [Common Tasks](#-common-tasks)
7. [Backend Deployment](#️-backend-deployment)
8. [Frontend Deployment](#️-frontend-deployment)
9. [Deployment Methods](#deployment-methods)
10. [Rollback Procedures](#rollback-procedures)
11. [Troubleshooting](#troubleshooting)
12. [CI/CD Integration](#cicd-integration)
13. [Best Practices](#-best-practices)
14. [Project Structure](#️-project-structure)
15. [Deployment Checklist](#-deployment-checklist)
16. [Key Information](#-key-information)
17. [Quick Links](#-quick-links)

---

## 🎯 Project Overview

An IoT oil detection system to analyze oil contents at the surface of a water body.

**System Components**:

- **IR Sensors**: To detect oil contents on the surface of water by analyzing the reflection of infra-red
- **ESP32**: To send data taken from sensors to a cloud native environment via LoRA
- **API Gateway**: Entrypoint for data ingress to AWS
- **Lambda**: Process sensor data and stores them in S3
- **S3**: Object storage for raw data from ESP32
- **Backend Service**: REST API to process raw object data and store them in RDS
- **Frontend Service**: React App which serves as analytical system & display of data in RDS
- **RDS PostgreSQL**: Processed data store
- **Application Load Balancer**: Public HTTPS/HTTP endpoint
- **Elastic Container Service**: Fargate service for deployment of containers

---

## ✅ Prerequisites

### Required Tools

- **AWS CLI** (v2.x recommended)

```zsh
aws --version
```

- **Docker** (v20.x or higher)

```zsh
docker --version
```

- **Terraform/OpenTofu**

> [!NOTE]
>
> Infrastructure has already been implemented  
> Check out [INFRA.md](./infra/INFRA.md) for more details.

```zsh
# Terraform
terraform --version

# OpenTofu
tofu --version
```

- **Make**

> [!NOTE]
>
> Usually pre-installed on Linux/Mac

```zsh
make --version
```

- **Node.js** (v18+ for frontend builds)

```zsh
node --version
```

### AWS Configuration

> [!TIP]  
> Ensure your AWS credentials are configured by running:  
> `aws configure list`
> or
> `cat ~/.aws/credentials`

```zsh
# Configure AWS credentials
aws configure

# Verify setup
aws sts get-caller-identity

# Set default region (if needed)
export AWS_REGION=ap-southeast-1

# Set environment (if needed)
export ENVIRONMENT=dev  # or prod, staging, etc.
```

---

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

---

## 🏗️ Infrastructure Setup

**1. Create RDS Credentials Secret**

> [!IMPORTANT]  
> Do this FIRST before running Terraform or OpenTofu!

```zsh
aws secretsmanager create-secret \
    --name rds_credentials \
    --secret-string '{"username": "<your_username>", "password": "<your_secure_password>"}'
```

or run this command if you have `make`:

```zsh
cd infra
make setup-secrets
```

**2. Initialize & Deploy Infrastructure**

```zsh
cd infra
terraform init
terraform plan
terraform apply
```

or alternatively, if you are using `opentofu`

```zsh
cd infra
make init
make validate
make plan
make pre-deployment   # only apply if all checks passed!
make apply
```

**Deployment time**: 10~15 minutes (due to RDS initialization & startup)

**3. Verify Infrastructure**

```zsh
# Show all outputs
make output

# Show key outputs
make output-summary

# Check infrastructure status
make status

# Verify AWS resources
make check-aws
```

---

## 🚀 Quick Deployment

### One-Command Deployment

From the project root:

```zsh
cd backend

# View available commands
make help

# Deploy everything
make deploy-all
```

**Deployment time**: 3-5 minutes per service

### Deploy Backend Service

```zsh
cd backend

# Deploy backend
make push-backend
```

### Deploy Frontend Service

```zsh
cd backend

# Deploy frontend
make push-frontend
```

### Utilizing Scripts

```zsh
cd infra

# Backend
./scripts/push-docker-image.sh

# Frontend
./scripts/push-frontend-image.sh
```

### View Available Commands

```zsh
cd backend
make help
```

---

## 🏥 Health Checks

### Check Service Health

```zsh
# From backend directory
make health-check

# Or manually
curl https://{alb_dns_name}/health
```

#### Expected response:

```
{"status":"ok"}
```

### Get ALB URL

```zsh
# From infra directory
cd infra
terraform output alb_dns_name

# From backend directory
cd backend
make info
```

### Check Service Status

```zsh
cd backend

# Check backend service
make status-backend

# Check frontend service
make status-frontend

# Check both
make status-all
```

---

## 📝 Common Tasks

### View Logs

```zsh
cd backend

# Backend service logs
make logs-backend

# Frontend service logs
make logs-frontend
```

### List ECR Images

```zsh
cd backend

# List recent images with timestamp
make list-images
```

### Rebuild & Redeploy

```zsh
# For backend
cd backend

# Rebuild
vim app.py

# Push to ECR
make push-backend

# For frontend
cd frontend

# Rebuild
vim src/App.js

# Push to ECR
make push-frontend
```

---

## ⚙️ Backend Deployment

### 1: Build the Docker Image

```zsh
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

### 2. Authenticate with ECR

The push script handles this automatically, or manually:

```zsh
cd infra
ECR_URI=$(tofu output -raw ecr_repository_url)
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI
```

**Authentication validity:** 12 hours

### 3. Tag the Image

```zsh
ECR_URI=$(cd infra && tofu output -raw ecr_repository_url)
docker tag ciot-backend:latest ${ECR_URI}:latest
docker tag ciot-backend:latest ${ECR_URI}:$(date +%Y%m%d-%H%M%S)
docker tag ciot-backend:latest ${ECR_URI}:$(git rev-parse --short HEAD)
```

**Tags created:**

- `latest` - Always points to most recent
- `20241203-143022` - Timestamp for rollback
- `a3f2c1d` - Git commit SHA for tracking

### 4. Push to ECR

```zsh
docker push ${ECR_URI}:latest
docker push ${ECR_URI}:$(date +%Y%m%d-%H%M%S)
docker push ${ECR_URI}:$(git rev-parse --short HEAD)
```

**Upload time:**

- First push: ~5-10 minutes (depends on connection)
- Subsequent pushes: ~1-3 minutes (only changed layers)

**Image size:** ~300-500 MB (compressed layers)

### 5. Update ECS Service

The push script does this automatically, or manually:

```zsh
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

### 6. Verify Backend Deployment

```zsh
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

## 🖥️ Frontend Deployment

### 1. Build the Docker Image

The frontend uses a multi-stage build:

```zsh
cd frontend
docker build -f dockerfile -t ciot-frontend:latest .
```

**What happens:**

- Stage 1: Node.js builder - installs dependencies and builds React app
- Stage 2: Nginx - serves static files from build
- Sets `REACT_APP_API_URL` to ALB DNS name
- Exposes port 80

**Build time:** ~5-10 minutes (first build), ~2-3 minutes (cached)

### 2. Authenticate with ECR

```zsh
cd infra
ECR_URI=$(tofu output -raw ecr_frontend_repository_url)
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI
```

### 3. Tag and Push Frontend Image

```zsh
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

### 4. Update Frontend ECS Service

```zsh
aws ecs update-service \
  --cluster ciot-cluster-dev \
  --service ciot-frontend-service-dev \
  --force-new-deployment \
  --region ap-southeast-1
```

### 5. Verify Frontend Deployment

```zsh
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

## ⛵ Deployment Methods

> [!TIP]  
> Checkout [Quick Deployment](#-quick-deployment) for the simplest approach!

### Method 1: Make Commands (Recommended)

```zsh
cd infra

# Deploy backend
make push-backend

# Deploy frontend
make push-frontend

# View infrastructure outputs
make output-summary
```

### Method 2: Deployment Scripts

**Backend:**

```zsh
cd infra/scripts
./push-docker-image.sh
```

**Frontend:**

```zsh
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

## 🔄 Rollback Procedures

### Quick Rollback to Previous Version

**Backend:**

```zsh
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

```zsh
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

```zsh
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

> [!CAUTION]  
> If the service is failing, follow the steps below.

```zsh
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

## 🛠️ Troubleshooting

> [!WARNING]  
> **Issue:** "no basic auth credentials"  
> **Cause:** Docker not authenticated with ECR

**Solution:**

```zsh
cd infra
ECR_URI=$(tofu output -raw ecr_repository_url)
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin $ECR_URI
```

> [!WARNING]  
> **Issue:** "repository does not exist"  
> **Cause:** ECR repository not created yet

**Solution:**

```zsh
cd infra
tofu apply -target=aws_ecr_repository.backend
tofu apply -target=aws_ecr_repository.frontend
```

> [!WARNING]  
> **Issue:** Build fails with "cannot find requirements.txt"  
> **Cause:** Running build from wrong directory

**Solution:**

```zsh
cd backend
docker build -f dockerfile -t ciot-backend:latest .
```

> [!WARNING]  
> **Issue:** Frontend build fails - "REACT_APP_API_URL not set"  
> **Cause:** Build arg missing during Docker build

**Solution:**

```zsh
cd infra
ALB_DNS=$(tofu output -raw alb_dns_name)
cd ../frontend
docker build \
  --build-arg REACT_APP_API_URL="http://${ALB_DNS}" \
  -f dockerfile \
  -t ciot-frontend:latest \
  .
```

> [!WARNING]  
> **Issue:** ECS task fails to start

**Debugging steps:**

```zsh
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

> [!WARNING]  
> **Issue:** "Task failed container health checks"  
> **Causes:**
>
> - Health check endpoint not responding
> - Container taking too long to start
> - Memory/CPU limits too low

**Solutions:**

```zsh
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

> [!WARNING]  
> **Issue:** "ResourceInitializationError: failed to validate logger args"  
> **Cause:** IAM role lacks CloudWatch Logs permissions

**Solution:**

```zsh
cd infra
# Verify IAM policy includes frontend log group
tofu plan -target=aws_iam_role_policy.ecs_execution_role_policy
tofu apply -target=aws_iam_role_policy.ecs_execution_role_policy
```

> [!WARNING]  
> **Issue:** Frontend shows CORS errors  
> **Cause:** Backend CORS middleware not configured for frontend URL

**Solution:**

Update `backend/app.py` to include frontend ALB URL in CORS origins, or use the ALB path-based routing (already configured).

> [!WARNING]  
> **Issue:** Frontend can't reach backend API  
> **Cause:** `REACT_APP_API_URL` not set correctly during build

**Solution:**

```zsh
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

## 🪢 CI/CD Integration

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

## 🔐 Best Practices

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

```zsh
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

## 🗂️ Project Structure

```zsh
ciot-oil-detection-project/
├── backend/
│   ├── app.py                     # Python backend API
│   ├── db_setup.py                # PostgreSQL database schema setup
│   ├── docker-compose.yml         # Local development
│   ├── dockerfile                 # Dockerfile for ECS
│   ├── requirements.txt           # Python dependencies
│   └── Makefile                   # Deployment commands
├── frontend/
│   ├── node_modules
│   ├── public
│   ├── src                        # React App files
│   └── dockerfile                 # Dockerfile for ECS
├── infra/
│   ├── *.tf/                      # Terraform configuration
│   ├── Makefile                   # Infrastructure commands
│   └── INFR.md                    # Infrastructure detailed docs
├── QUICK-START.md               # Detailed quick start
├── README.md                    # This file
└── LICENSE
```

---

## 📌 Deployment Checklist

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

## 🎯 Key Information

|        **Component**        |            **Value**             |
| :-------------------------: | :------------------------------: |
|       **AWS Region**        |   `ap-southeast-1` (Singapore)   |
|       **ECS Cluster**       |        `ciot-cluster-dev`        |
| **Backend ECR Repository**  |        `ciot-backend-dev`        |
| **Frontend ECR Repository** |       `ciot-frontend-dev`        |
|        **Database**         |       `postgresql` on RDS        |
|        **Services**         |      `backend`, `frontend`       |
|      **Load Balancer**      |      `ciot-backend-alb-dev`      |
|         **Domain**          | Configurable in terraform.tfvars |

---

## 🔗 Quick Links

> [!TIP]  
> Checkout [README.md](./README.md) for full commands via `make help`

After deployment, get important URLs:

```zsh
cd infra
make output-summary
```

This will show:

- **Frontend URL** - Access your React application
- **Backend API URL** - FastAPI endpoints
- **ECS Cluster Name** - For service management
- **ALB DNS Name** - Load balancer endpoint

---

## 📚 Additional Resources

- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [React Documentation](https://react.dev/)

---

**Last Updated:** December 2025  
**Project:** IoT Oil Detection System  
**Maintained By:** CIOT Team 1

> [!TIP]  
> Bookmark this file and keep it open while working!  
> For a more detailed documentation on this project checkout
> [README.md](README.md)!

This project is an undertaking of the [50.046 - Cloud Computing & IoT](https://www.sutd.edu.sg/course/50-046-cloud-computing-and-internet-of-things/) module during Fall 2025 under the **Information Systems Technology & Design (ISTD)** faculty the **Singapore University of Technology & Design (SUTD)**.

**Contributors**:  
Copyright &copy; Vancence &nbsp;|&nbsp; CSD &nbsp;|&nbsp; SUTD  
Copyright &copy; Andrew &nbsp;|&nbsp; CSD &nbsp;|&nbsp; SUTD  
Copyright &copy; Joshua &nbsp;|&nbsp; CSD &nbsp;|&nbsp; SUTD  
Copyright &copy; Ammar &nbsp;|&nbsp; CSD &nbsp;|&nbsp; SUTD

<a href="https://github.com/vancenceho/ciot-oil-detection-project/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=vancenceho/ciot-oil-detection-project" />
</a>

---

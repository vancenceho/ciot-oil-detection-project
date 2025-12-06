# 50.046 Oil Detection System Infrastructure Documentation

Complete guide to the CIOT Oil Detection System infrastructure architecture, components, and management.

## 📋 Table of Contents

1. [Infrastructure Overview](#-infrastructure-overview)
2. [Architecture Diagram](#-architecture-diagram)
3. [Network Architecture](#-network-architecture)
4. [Core Components](#-core-components)
5. [Security Architecture](#-security-architecture)
6. [Terraform Structure](#-terraform-structure)
7. [Resource Configuration](#-resource-configuration)
8. [Infrastructure Management](#-infrastructure-management)
9. [Cost Optimization](#-cost-optimization)
10. [Scaling Considerations](#-scaling-considerations)
11. [Disaster Recovery](#-disaster-recovery)
12. [Monitoring & Observability](#-monitoring--observability)
13. [Troubleshooting](#-troubleshooting)

---

## 🏗️ Infrastructure Overview

The CIOT Oil Detection System is deployed on **AWS** using a serverless and containerized architecture. The infrastructure is defined using **Terraform/OpenTofu** and follows Infrastructure as Code (IaC) best practices.

### Key Characteristics

- **Region**: `ap-southeast-1` (Singapore)
- **Environment**: `dev` (configurable via variables)
- **Deployment Model**: Multi-AZ for high availability
- **Compute**: Serverless (Lambda) + Containerized (ECS Fargate)
- **Database**: Managed RDS PostgreSQL
- **Storage**: S3 for object storage
- **Networking**: VPC with public/private subnets

### Infrastructure Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet / ESP32                         │
└──────────────────────┬──────────────────────────────────────┘
                      │
         ┌────────────▼────────────┐
         │   API Gateway (HTTP)    │
         └────────────┬────────────┘
                      │
         ┌────────────▼────────────┐
         │   Lambda Function       │
         │   (Data Ingestion)      │
         └────────────┬────────────┘
                      │
         ┌────────────▼────────────┐
         │   S3 Bucket             │
         │   (raw/cleaned/processed)│
         └────────────┬────────────┘
                      │
         ┌────────────▼────────────┐
         │   Application Load      │
         │   Balancer (ALB)        │
         └──────┬──────────┬───────┘
                │          │
    ┌───────────▼──┐  ┌────▼──────────┐
    │ ECS Backend  │  │ ECS Frontend  │
    │ (Fargate)    │  │ (Fargate)     │
    └──────┬───────┘  └───────────────┘
           │
    ┌──────▼──────────────┐
    │   RDS PostgreSQL    │
    │   (Private Subnet)  │
    └─────────────────────┘
```

---

## 🗺️ Architecture Diagram

For a visual representation, check out the proof of concept below:

![architecture-diagram](../assets/images/ciot-architecture-diagram.png)

---

## 🌐 Network Architecture

### VPC Configuration

- **CIDR Block**: `10.0.0.0/16` (configurable via `vpc_cidr` variable)
- **DNS Support**: Enabled
- **DNS Hostnames**: Enabled

### Subnet Design

The infrastructure uses a **multi-AZ** subnet architecture across 2 availability zones:

#### Public Subnets

- **Purpose**: ECS Fargate tasks, ALB, Internet Gateway
- **CIDR**: `10.0.10.0/24`, `10.0.11.0/24` (one per AZ)
- **Internet Access**: Direct via Internet Gateway
- **Resources**:
  - Application Load Balancer
  - ECS Backend Service (Fargate)
  - ECS Frontend Service (Fargate)

#### Private Subnets

- **Purpose**: RDS database (isolated from internet)
- **CIDR**: `10.0.0.0/24`, `10.0.1.0/24` (one per AZ)
- **Internet Access**: None (no NAT Gateway)
- **Resources**:
  - RDS PostgreSQL instance
  - DB Subnet Group

### Routing

#### Public Route Table

- Default route: `0.0.0.0/0` → Internet Gateway
- Associated with: Public subnets

#### Private Route Table

- Local VPC routing only
- No internet gateway (RDS doesn't need internet access)
- Associated with: Private subnets

### Availability Zones

- **Primary AZ**: `ap-southeast-1a`
- **Secondary AZ**: `ap-southeast-1b`

Both subnets and RDS are distributed across these AZs for high availability.

---

## 🧩 Core Components

### 1. Virtual Private Cloud (VPC)

**File**: `vpc.tf`

- Isolated network environment
- Multi-AZ deployment
- Public/private subnet separation
- Internet Gateway for public access

**Key Resources**:

- `aws_vpc.main` - Main VPC
- `aws_internet_gateway.main` - Internet Gateway
- `aws_subnet.public[*]` - Public subnets (2)
- `aws_subnet.private[*]` - Private subnets (2)
- `aws_route_table.public` - Public routing
- `aws_route_table.private` - Private routing

### 2. Application Load Balancer (ALB)

**File**: `alb.tf`

- **Type**: Application Load Balancer (Layer 7)
- **Scheme**: Internet-facing
- **Protocol**: HTTP (HTTPS optional, commented out)
- **Features**:
  - HTTP/2 enabled
  - Cross-zone load balancing
  - Path-based routing

**Routing Rules**:

- `/health`, `/db-health`, `/readings-latest*` → Backend target group
- Default (all other paths) → Frontend target group

**Target Groups**:

- **Backend TG**: Port 8080, health check on `/health`
- **Frontend TG**: Port 80, health check on `/`

**Security Group**:

- Ingress: HTTP (80) from `0.0.0.0/0`
- Egress: All traffic

### 3. Elastic Container Service (ECS)

**File**: `ecs.tf`

#### ECS Cluster

- **Name**: `ciot-cluster-{environment}`
- **Launch Type**: Fargate (serverless containers)
- **Container Insights**: Enabled

#### Backend Service

- **Task Definition**: `ciot-backend-{environment}`
- **CPU**: 512 units (0.5 vCPU)
- **Memory**: 2048 MB (2 GB)
- **Port**: 8080
- **Desired Count**: 1 (configurable)
- **Health Check**: `curl -f http://localhost:8080/health`
- **Logs**: CloudWatch Logs (`/ecs/ciot-backend-{environment}`)

**Environment Variables**:

- `ENVIRONMENT` - Deployment environment
- `RDS_HOST` - RDS endpoint address
- `RDS_PORT` - RDS port (5432)
- `RDS_DB_NAME` - Database name
- `RDS_SECRET_ARN` - Secrets Manager ARN for credentials
- `S3_BUCKET` - S3 bucket name

#### Frontend Service

- **Task Definition**: `ciot-frontend-{environment}`
- **CPU**: 256 units (0.25 vCPU)
- **Memory**: 512 MB
- **Port**: 80
- **Desired Count**: 1 (configurable)
- **Health Check**: `wget --spider http://localhost/`
- **Logs**: CloudWatch Logs (`/ecs/ciot-frontend-{environment}`)

**Environment Variables**:

- `ENVIRONMENT` - Deployment environment
- `REACT_APP_API_URL` - Backend API URL (ALB DNS)

### 4. Relational Database Service (RDS)

**File**: `rds.tf`

- **Engine**: PostgreSQL
- **Instance Class**: `db.t3.micro`
- **Storage**: 20 GB (gp3), auto-scales to 100 GB
- **Encryption**: Enabled
- **Multi-AZ**: Disabled (can be enabled for production)
- **Backup**: 1 day retention, daily at 03:00-04:00 UTC
- **Maintenance**: Monday 04:00-05:00 UTC
- **Network**: Private subnets only
- **Public Access**: Disabled
- **Deletion Protection**: Disabled (dev environment)

**Database Configuration**:

- **Name**: `ciotdb`
- **Port**: 5432
- **Credentials**: Stored in AWS Secrets Manager

**Security Group**:

- Ingress: PostgreSQL (5432) from VPC CIDR and ECS tasks
- Egress: All traffic

### 5. Elastic Container Registry (ECR)

**File**: `ecr.tf`

Two repositories for container images:

#### Backend Repository

- **Name**: `ciot-backend-{environment}`
- **Lifecycle Policy**: Keep last 10 images

#### Frontend Repository

- **Name**: `ciot-frontend-{environment}`
- **Lifecycle Policy**: Keep last 10 images

**Image Tagging Strategy**:

- `latest` - Most recent deployment
- `{timestamp}` - Deployment timestamp (YYYYMMDD-HHMMSS)
- `{git-sha}` - Git commit SHA

### 6. Simple Storage Service (S3)

**File**: `s3-bucket.tf`

- **Bucket Name**: `ciot-buoy-data-{environment}-test`
- **Force Destroy**: Enabled (for dev environment)

**Folder Structure**:

- `raw/` - Raw sensor data from ESP32/Lambda
- `cleaned/` - Processed/cleaned data
- `processed/` - Final processed data (from AWS Glue, if configured)

**Access Control**: Private (bucket owner only)

### 7. Lambda Function

**File**: `lambda.tf`

- **Function Name**: `buoy-data-ingest-{environment}`
- **Runtime**: Python 3.11
- **Handler**: `handler.lambda_handler`
- **Package**: `scripts/lambda_ingest.zip`
- **Role**: IAM role with S3 write permissions

**Environment Variables**:

- `BUCKET_NAME` - S3 bucket name

**Permissions**:

- Write to S3 (`s3:PutObject` on `raw/*`)
- CloudWatch Logs

### 8. API Gateway

**File**: `api-gateway.tf`

- **Type**: HTTP API (v2)
- **Name**: `oil-data-ingest-api-{environment}`
- **Route**: `POST /ingest`
- **Integration**: Lambda proxy integration
- **Stage**: `$default` (auto-deploy enabled)

**Integration**:

- Lambda function: `buoy-data-ingest-{environment}`
- Payload format: 2.0

---

## 🔒 Security Architecture

### Security Groups

#### ALB Security Group

- **Name**: `ciot-alb-sg-{environment}`
- **Ingress**: HTTP (80) from Internet
- **Egress**: All traffic

#### ECS Tasks Security Group

- **Name**: `ciot-ecs-tasks-sg-{environment}`
- **Ingress**:
  - HTTP (8080) from ALB (backend)
  - HTTP (80) from ALB (frontend)
- **Egress**: All traffic

#### RDS Security Group

- **Name**: `ciot-rds-sg-{environment}`
- **Ingress**:
  - PostgreSQL (5432) from VPC CIDR
  - PostgreSQL (5432) from ECS tasks security group
- **Egress**: All traffic

### IAM Roles

#### Lambda Execution Role

- **Name**: `oil-data-ingest-lambda-role`
- **Permissions**:
  - S3: `PutObject` on `raw/*`
  - CloudWatch Logs: Create log groups/streams, put events

#### ECS Task Execution Role

- **Name**: `ciot-ecs-execution-role-{environment}`
- **Permissions**:
  - ECR: Pull images
  - CloudWatch Logs: Write logs
  - Secrets Manager: Get RDS credentials

#### ECS Task Role

- **Name**: `ciot-ecs-task-role-{environment}`
- **Permissions**:
  - S3: Get/Put objects, list bucket
  - CloudWatch Logs: Write logs
  - Secrets Manager: Get RDS credentials

### Secrets Management

- **Service**: AWS Secrets Manager
- **Secret Name**: `rds_credentials` (must be created before Terraform apply)
- **Format**: JSON with `username` and `password`
- **Access**: ECS tasks retrieve credentials at runtime

**Setup Command**:

```bash
cd infra
make setup-secrets
```

---

## 📁 Terraform Structure

### File Organization

```
infra/
├── providers.tf          # AWS provider configuration
├── variables.tf          # Input variables
├── outputs.tf           # Output values
├── vpc.tf               # VPC, subnets, routing
├── alb.tf               # Application Load Balancer
├── ecs.tf               # ECS cluster, services, task definitions
├── ecr.tf               # Container registries
├── rds.tf               # PostgreSQL database
├── s3-bucket.tf         # S3 bucket and folders
├── lambda.tf            # Lambda function
├── api-gateway.tf       # API Gateway
├── iam.tf               # IAM roles and policies
├── secrets.tf           # Secrets Manager data source
├── Makefile             # Infrastructure management commands
└── scripts/             # Helper scripts
    ├── setup-secrets.sh
    ├── push-docker-image.sh
    ├── push-frontend-image.sh
    ├── check-status.sh
    └── validate-pre-deployment.sh
```

### Key Variables

| Variable               | Default                                  | Description             |
| ---------------------- | ---------------------------------------- | ----------------------- |
| `region`               | `ap-southeast-1`                         | AWS region              |
| `environment`          | `dev`                                    | Deployment environment  |
| `vpc_cidr`             | `10.0.0.0/16`                            | VPC CIDR block          |
| `availability_zones`   | `["ap-southeast-1a", "ap-southeast-1b"]` | AZs for subnets         |
| `ecs_task_cpu`         | `512`                                    | Backend CPU units       |
| `ecs_task_memory`      | `2048`                                   | Backend memory (MB)     |
| `ecs_desired_count`    | `1`                                      | Desired task count      |
| `backend_port`         | `8080`                                   | Backend container port  |
| `frontend_port`        | `80`                                     | Frontend container port |
| `frontend_task_cpu`    | `256`                                    | Frontend CPU units      |
| `frontend_task_memory` | `512`                                    | Frontend memory (MB)    |

### Key Outputs

| Output                        | Description                    |
| ----------------------------- | ------------------------------ |
| `alb_dns_name`                | ALB DNS name (public endpoint) |
| `backend_api_url`             | Full backend API URL           |
| `frontend_url`                | Frontend application URL       |
| `ecr_repository_url`          | Backend ECR repository URL     |
| `ecr_frontend_repository_url` | Frontend ECR repository URL    |
| `ecs_cluster_name`            | ECS cluster name               |
| `rds_endpoint`                | RDS database endpoint          |
| `rds_address`                 | RDS database address           |
| `rds_port`                    | RDS database port              |
| `rds_database_name`           | Database name                  |
| `ingest_api_url`              | API Gateway endpoint           |

---

## ⚙️ Resource Configuration

### Resource Naming Convention

All resources follow the pattern: `ciot-{resource-type}-{environment}`

Examples:

- `ciot-vpc-dev`
- `ciot-cluster-dev`
- `ciot-backend-service-dev`
- `ciot-rds-dev`

### Resource Tags

All resources are tagged with:

- `Name`: Resource name
- `Environment`: Deployment environment (e.g., `dev`)

### Resource Limits & Quotas

**ECS Fargate**:

- Backend: 512 CPU units, 2048 MB memory
- Frontend: 256 CPU units, 512 MB memory
- Max tasks per service: Configurable via `ecs_desired_count`

**RDS**:

- Instance: `db.t3.micro` (1 vCPU, 1 GB RAM)
- Storage: 20-100 GB (auto-scaling)
- Max connections: ~87 (based on instance class)

**Lambda**:

- Memory: Default (128 MB - 10 GB)
- Timeout: Default (3 seconds - 15 minutes)
- Concurrent executions: Account limit

**S3**:

- Bucket size: Unlimited
- Object size: 5 TB max

---

## 🛠️ Infrastructure Management

### Prerequisites

Before managing infrastructure:

1. **AWS CLI configured**:

   ```bash
   aws configure list
   ```

2. **Terraform/OpenTofu installed**:

   ```bash
   terraform version  # or tofu version
   ```

3. **RDS credentials secret created**:
   ```bash
   cd infra
   make setup-secrets
   ```

### Common Commands

#### Initialization

```bash
cd infra
make init          # Initialize Terraform/OpenTofu
```

#### Planning

```bash
make plan          # Preview changes
make plan-destroy   # Preview destroy plan
```

#### Validation

```bash
make validate      # Validate configuration
make pre-deployment # Full pre-deployment checks
```

#### Deployment

```bash
make apply         # Deploy infrastructure
```

#### Inspection

```bash
make output        # Show all outputs
make output-summary # Show key outputs
make status        # Check infrastructure status
make check-drift   # Check for configuration drift
```

#### Cleanup

```bash
make destroy       # Destroy all infrastructure (WARNING)
```

### State Management

#### View State

```bash
make list-resources           # List all resources
make show-resource RESOURCE=aws_db_instance.main  # Show resource details
```

#### State Operations

```bash
make refresh      # Refresh state from AWS
make backup-state # Backup state file
```

#### Import/Export

```bash
make import RESOURCE=aws_s3_bucket.buoy_data ID=my-bucket
```

### Advanced Operations

#### Taint/Untaint Resources

```bash
make taint RESOURCE=aws_ecs_service.backend    # Force recreation
make untaint RESOURCE=aws_ecs_service.backend  # Remove taint
```

#### Force Unlock

```bash
make unlock LOCK_ID=<lock-id>  # Unlock stuck state
```

#### Generate Dependency Graph

```bash
make graph  # Requires graphviz (brew install graphviz)
```

---

## 💰 Cost Optimization

### Current Cost Estimates (Dev Environment)

**Monthly Estimates** (approximate):

| Service                | Configuration                  | Estimated Cost     |
| ---------------------- | ------------------------------ | ------------------ |
| RDS (db.t3.micro)      | 20 GB storage                  | ~$15-20            |
| ECS Fargate (Backend)  | 0.5 vCPU, 2 GB                 | ~$30-40            |
| ECS Fargate (Frontend) | 0.25 vCPU, 0.5 GB              | ~$10-15            |
| ALB                    | 1 ALB                          | ~$20-25            |
| S3                     | 1 GB storage, minimal requests | ~$0.50             |
| Lambda                 | 1M requests/month              | ~$0.20             |
| API Gateway            | 1M requests/month              | ~$1.00             |
| CloudWatch Logs        | 1 GB/month                     | ~$0.50             |
| **Total**              |                                | **~$80-120/month** |

### Cost Optimization Tips

1. **RDS**:

   - Use `db.t3.micro` for dev (free tier eligible for first year)
   - Enable auto-scaling storage (pay only for what you use)
   - Consider stopping RDS when not in use (dev only)

2. **ECS Fargate**:

   - Right-size CPU/memory based on actual usage
   - Scale to 0 during non-business hours (dev only)
   - Use Spot pricing for non-critical workloads (not configured)

3. **ALB**:

   - Single ALB handles both frontend and backend (cost-efficient)
   - Consider using NLB for higher throughput (if needed)

4. **S3**:

   - Enable lifecycle policies to move old data to Glacier
   - Use S3 Intelligent-Tiering for variable access patterns

5. **CloudWatch**:

   - Set log retention to 7 days (already configured)
   - Use log filters to reduce stored data

6. **Lambda**:
   - Optimize function execution time
   - Use provisioned concurrency only if needed

### Production Cost Considerations

For production, consider:

- Multi-AZ RDS (adds ~2x cost)
- Higher ECS task counts (2+ for high availability)
- Reserved capacity for predictable workloads
- CloudWatch alarms and dashboards
- WAF for ALB (if needed)

---

## 📈 Scaling Considerations

### Horizontal Scaling

#### ECS Services

- **Current**: 1 task per service
- **Scaling**: Increase `ecs_desired_count` variable
- **Auto-scaling**: Can be configured via ECS Service Auto Scaling

**Example**: Scale backend to 3 tasks

```hcl
variable "ecs_desired_count" {
  default = 3
}
```

#### RDS

- **Vertical Scaling**: Change instance class (e.g., `db.t3.small`, `db.t3.medium`)
- **Horizontal Scaling**: Enable read replicas
- **Storage Scaling**: Auto-scaling enabled (20-100 GB)

### Performance Tuning

#### ECS Task Resources

- **Backend**: Increase CPU/memory if experiencing performance issues
- **Frontend**: Usually sufficient at 256 CPU / 512 MB

#### RDS Performance

- Enable Performance Insights (not configured)
- Add read replicas for read-heavy workloads
- Use connection pooling in application

#### ALB

- Enable HTTP/2 (already enabled)
- Configure idle timeout based on workload
- Use sticky sessions if needed (not configured)

### High Availability

**Current Configuration**:

- ✅ Multi-AZ subnets
- ✅ ALB across multiple AZs
- ✅ RDS in private subnets (can enable Multi-AZ)
- ❌ Single ECS task per service (not HA)
- ❌ RDS Multi-AZ disabled

**Production Recommendations**:

- Enable RDS Multi-AZ
- Set `ecs_desired_count` to 2+ for each service
- Configure ECS service auto-scaling
- Add CloudWatch alarms for service health

---

## 🚨 Disaster Recovery

### Backup Strategy

#### RDS Backups

- **Automated Backups**: Enabled (1 day retention)
- **Backup Window**: 03:00-04:00 UTC
- **Snapshot**: Manual snapshots can be created

**Create Manual Snapshot**:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier ciot-db-dev \
  --db-snapshot-identifier ciot-db-dev-manual-$(date +%Y%m%d) \
  --region ap-southeast-1
```

#### S3 Data

- **Versioning**: Not enabled (can be enabled)
- **Cross-Region Replication**: Not configured
- **Backup**: Manual or automated via lifecycle policies

#### Infrastructure State

- **Terraform State**: Stored locally (consider remote state)
- **Backup**: Use `make backup-state` before major changes

### Recovery Procedures

#### RDS Recovery

1. Restore from automated backup:

   ```bash
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier ciot-db-dev-restored \
     --db-snapshot-identifier <snapshot-id>
   ```

2. Point-to-in-time recovery (if enabled)

#### ECS Service Recovery

1. Check service status: `make status`
2. View logs: `make logs-backend` or `make logs-frontend`
3. Force new deployment: Update ECS service
4. Rollback to previous task definition if needed

#### Infrastructure Recovery

1. Restore Terraform state from backup
2. Run `terraform refresh` to sync state
3. Run `terraform plan` to identify drift
4. Run `terraform apply` to restore resources

### Disaster Recovery Testing

**Recommended**:

- Test RDS snapshot restore quarterly
- Test ECS service rollback procedures
- Document recovery runbooks
- Test infrastructure recreation from scratch

---

## 📊 Monitoring & Observability

### CloudWatch Logs

#### ECS Logs

- **Backend**: `/ecs/ciot-backend-{environment}`
- **Frontend**: `/ecs/ciot-frontend-{environment}`
- **Retention**: 7 days

**View Logs**:

```bash
# Backend
aws logs tail /ecs/ciot-backend-dev --follow --region ap-southeast-1

# Frontend
aws logs tail /ecs/ciot-frontend-dev --follow --region ap-southeast-1

# Lambda
make logs-lambda
```

#### Lambda Logs

- **Log Group**: `/aws/lambda/buoy-data-ingest-{environment}`
- **Retention**: Default (never expire)

### CloudWatch Metrics

#### ECS Metrics

- CPU utilization
- Memory utilization
- Task count
- Service health

#### ALB Metrics

- Request count
- Target response time
- HTTP status codes
- Active connection count

#### RDS Metrics

- CPU utilization
- Database connections
- Read/Write IOPS
- Free storage space

### Container Insights

- **Status**: Enabled on ECS cluster
- **Metrics**: Available in CloudWatch Console
- **Dashboard**: Can be created in CloudWatch

### Health Checks

#### ALB Health Checks

- **Backend**: `/health` endpoint
- **Frontend**: `/` endpoint
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy Threshold**: 2
- **Unhealthy Threshold**: 3

#### ECS Container Health Checks

- **Backend**: `curl -f http://localhost:8080/health`
- **Frontend**: `wget --spider http://localhost/`
- **Start Period**: 60 seconds (backend), 30 seconds (frontend)

### Recommended Alarms

**Production Alarms** (not configured, recommended):

- ECS service task count < desired
- RDS CPU utilization > 80%
- RDS free storage < 20%
- ALB unhealthy target count > 0
- Lambda error rate > 5%

---

## 🔧 Troubleshooting

### Common Issues

#### Issue: Terraform State Locked

**Symptoms**: `Error acquiring the state lock`

**Solution**:

```bash
# Find lock ID from error message
make unlock LOCK_ID=<lock-id>

# Or force unlock (use with caution)
terraform force-unlock <lock-id>
```

#### Issue: RDS Credentials Not Found

**Symptoms**: `Secret not found: rds_credentials`

**Solution**:

```bash
cd infra
make setup-secrets
```

#### Issue: ECS Task Failing to Start

**Symptoms**: Tasks in `STOPPED` state, health checks failing

**Debugging**:

```bash
# Check service events
aws ecs describe-services \
  --cluster ciot-cluster-dev \
  --services ciot-backend-service-dev \
  --region ap-southeast-1 \
  --query 'services[0].events[0:10]'

# Check task logs
make logs-backend

# Check task definition
aws ecs describe-task-definition \
  --task-definition ciot-backend-dev \
  --region ap-southeast-1
```

**Common Causes**:

- Image not found in ECR
- Insufficient CPU/memory
- Health check failing
- IAM permissions missing
- Secrets Manager access denied

#### Issue: ALB Target Unhealthy

**Symptoms**: Targets showing as unhealthy in ALB

**Debugging**:

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-southeast-1

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=ciot-*" \
  --region ap-southeast-1
```

**Common Causes**:

- Security group rules blocking traffic
- Health check path incorrect
- Container not listening on expected port
- Task not running

#### Issue: RDS Connection Timeout

**Symptoms**: Backend cannot connect to RDS

**Debugging**:

```bash
# Verify RDS endpoint
make output-summary | grep RDS

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids <rds-security-group-id> \
  --region ap-southeast-1

# Test connection from ECS task (if possible)
```

**Common Causes**:

- Security group not allowing ECS tasks
- RDS in wrong subnet
- Incorrect endpoint/port
- Credentials incorrect

#### Issue: S3 Access Denied

**Symptoms**: Lambda or ECS cannot write to S3

**Debugging**:

```bash
# Check IAM policies
aws iam get-role-policy \
  --role-name <role-name> \
  --policy-name <policy-name> \
  --region ap-southeast-1
```

**Common Causes**:

- IAM policy missing S3 permissions
- Bucket policy blocking access
- Incorrect bucket name

### Infrastructure Drift

**Check for drift**:

```bash
make check-drift
```

**If drift detected**:

```bash
make plan  # Review changes
make apply # Apply to fix drift
```

### Resource Limits

**Check service quotas**:

```bash
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0263D0A3 \
  --region ap-southeast-1
```

**Common Limits**:

- VPCs per region: 5 (soft limit)
- ECS services per cluster: 1000
- RDS instances per region: 40
- Lambda concurrent executions: 1000 (default)

---

## 📚 Additional Resources

### AWS Documentation

- [ECS Fargate](https://docs.aws.amazon.com/ecs/latest/developerguide/AWS_Fargate.html)
- [RDS PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/)

### Terraform Documentation

- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### Project Documentation

- [README.md](../README.md) - Project overview
- [QUICK-START.md](../QUICK-START.md) - Deployment guide

---

## 🎯 Quick Reference

### Get Infrastructure URLs

```bash
cd infra
make output-summary
```

### Check Service Status

```bash
make status
```

### View Logs

```bash
make logs-backend
make logs-frontend
make logs-lambda
```

### Deploy Infrastructure

```bash
make init
make plan
make apply
```

### Destroy Infrastructure

```bash
make destroy  # WARNING: Destructive!
```

---

**Last Updated**: December 2025  
**Maintained By**: CIOT Team 1  
**Project**: 50.046 Cloud Computing & IoT - Oil Detection System

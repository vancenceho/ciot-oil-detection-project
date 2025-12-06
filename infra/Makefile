.PHONY: help init plan plan-destroy apply destroy validate fmt output clean check-drift logs status

# Configuration
REGION ?= ap-southeast-1
ENVIRONMENT ?= dev

# Colors
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
BLUE = \033[0;34m
NC = \033[0m

help: ## Show this help message
	@echo "$(BLUE)=== CIOT Oil Detection Project - Infrastructure Management ===$(NC)"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Quick Start:$(NC)"
	@echo "  make pre-deployment  # Validate prerequisites"
	@echo "  make setup-secrets   # Create RDS credentials secret"
	@echo "  make init            # Initialize OpenTofu"
	@echo "  make plan            # Preview changes"
	@echo "  make apply           # Apply infrastructure"
	@echo "  make output          # Show all outputs"

init: ## Initialize OpenTofu
	@echo "$(YELLOW)Initializing OpenTofu...$(NC)"
	tofu init
	@echo "$(GREEN)✓ Initialization complete$(NC)"

validate: ## Validate OpenTofu configuration
	@echo "$(YELLOW)Validating OpenTofu configuration...$(NC)"
	tofu validate
	@echo "$(GREEN)✓ Configuration is valid$(NC)"

fmt: ## Format OpenTofu files
	@echo "$(YELLOW)Formatting OpenTofu files...$(NC)"
	tofu fmt -recursive
	@echo "$(GREEN)✓ Formatting complete$(NC)"

plan: ## Show execution plan
	@echo "$(YELLOW)Creating execution plan...$(NC)"
	tofu plan
	@echo "$(GREEN)✓ Plan complete$(NC)"

plan-destroy: ## Preview what will be destroyed (safe, read-only)
	@echo "$(YELLOW)Previewing destroy plan...$(NC)"
	@echo "$(RED)This will show what resources will be destroyed$(NC)"
	@echo ""
	tofu plan -destroy
	@echo "$(GREEN)✓ Destroy plan preview complete$(NC)"

apply: ## Apply infrastructure changes
	@echo "$(YELLOW)Applying infrastructure changes...$(NC)"
	tofu apply
	@echo "$(GREEN)✓ Apply complete$(NC)"
	@echo ""
	@echo "$(YELLOW)Important outputs:$(NC)"
	@$(MAKE) output-summary

destroy: ## Destroy all infrastructure (WARNING: Destructive)
	@echo "$(RED)WARNING: This will destroy all infrastructure!$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to cancel, or wait 5 seconds to continue...$(NC)"
	@sleep 5
	tofu destroy

output: ## Show all OpenTofu outputs
	@tofu output

output-json: ## Show all outputs in JSON format
	@tofu output -json

output-summary: ## Show summary of key outputs
	@echo ""
	@echo "$(BLUE)=== Key Infrastructure Outputs ===$(NC)"
	@echo ""
	@echo "$(YELLOW)Frontend URL:$(NC)"
	@tofu output -raw frontend_url 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)API Gateway URL:$(NC)"
	@tofu output -raw ingest_api_url 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)Backend API URL:$(NC)"
	@tofu output -raw backend_api_url 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)ECS Cluster Name:$(NC)"
	@tofu output -raw ecs_cluster_name 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)RDS Endpoint:$(NC)"
	@tofu output -raw rds_endpoint 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)RDS Address:$(NC)"
	@tofu output -raw rds_address 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)RDS Port:$(NC)"
	@tofu output -raw rds_port 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "$(YELLOW)Database Name:$(NC)"
	@tofu output -raw rds_database_name 2>/dev/null || echo "  Not available"
	@echo ""

check-drift: ## Check for configuration drift
	@echo "$(YELLOW)Checking for infrastructure drift...$(NC)"
	@tofu plan -detailed-exitcode > /dev/null 2>&1; \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -eq 0 ]; then \
		echo "$(GREEN)✓ No drift detected$(NC)"; \
	elif [ $$EXIT_CODE -eq 2 ]; then \
		echo "$(YELLOW)⚠ Drift detected - run 'make plan' to see details$(NC)"; \
	else \
		echo "$(RED)✗ Error checking drift$(NC)"; \
	fi

status: ## Show infrastructure status
	@chmod +x scripts/check-status.sh
	@./scripts/check-status.sh

pre-deployment: ## Validate prerequisites before deployment
	@echo "$(YELLOW)Running pre-deployment validation...$(NC)"
	@chmod +x scripts/validate-pre-deployment.sh
	@./scripts/validate-pre-deployment.sh

setup-secrets: ## Create RDS credentials secret in AWS Secrets Manager
	@echo "$(YELLOW)Setting up RDS credentials secret...$(NC)"
	@chmod +x scripts/setup-secrets.sh
	@./scripts/setup-secrets.sh

push-backend: ## Build and push Docker image to ECR
	@echo "$(YELLOW)Building and pushing Docker image...$(NC)"
	@chmod +x scripts/push-docker-image.sh
	@./scripts/push-docker-image.sh

push-frontend: ## Build and push Frontend Docker image to ECR
	@echo "$(YELLOW)Building and pushing Frontend Docker image...$(NC)"
	@chmod +x scripts/push-frontend-image.sh
	@./scripts/push-frontend-image.sh

deploy-all: ## Deploy all services
	@echo "$(YELLOW)Deploying all services...$(NC)"
	@$(MAKE) push-backend
	@$(MAKE) push-frontend
	@echo "$(GREEN)✓ Deployment complete$(NC)"

logs-lambda: ## View Lambda function logs
	@echo "$(YELLOW)Fetching Lambda logs...$(NC)"
	@LAMBDA_NAME="buoy-data-ingest-$(ENVIRONMENT)" && \
	LOG_GROUP="/aws/lambda/$$LAMBDA_NAME" && \
	aws logs tail $$LOG_GROUP --follow --region $(REGION) || \
	echo "$(RED)✗ Log group not found or Lambda not deployed$(NC)"

list-resources: ## List all managed resources
	@echo "$(YELLOW)Listing OpenTofu-managed resources...$(NC)"
	@tofu state list

show-resource: ## Show details of a resource (usage: make show-resource RESOURCE=aws_db_instance.main)
	@if [ -z "$(RESOURCE)" ]; then \
		echo "$(RED)Error: RESOURCE parameter required$(NC)"; \
		echo "Usage: make show-resource RESOURCE=aws_db_instance.main"; \
		exit 1; \
	fi
	@tofu state show $(RESOURCE)

graph: ## Generate dependency graph (requires graphviz)
	@echo "$(YELLOW)Generating dependency graph...$(NC)"
	@tofu graph | dot -Tpng > infrastructure-graph.png && \
	echo "$(GREEN)✓ Graph saved to infrastructure-graph.png$(NC)" || \
	echo "$(RED)✗ Failed (install graphviz: brew install graphviz)$(NC)"

clean: ## Clean OpenTofu cache and state backups
	@echo "$(YELLOW)Cleaning OpenTofu cache...$(NC)"
	@rm -rf .terraform/
	@rm -f terraform.tfstate.*.backup
	@rm -f infrastructure-graph.png
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

check-aws: ## Verify AWS credentials and configuration
	@echo "$(YELLOW)Checking AWS configuration...$(NC)"
	@echo ""
	@echo "$(BLUE)AWS Identity:$(NC)"
	@aws sts get-caller-identity --output table
	@echo ""
	@echo "$(BLUE)Region:$(NC) $(REGION)"
	@echo ""
	@echo "$(BLUE)Default Region:$(NC)"
	@aws configure get region || echo "  Not configured"

import: ## Import existing AWS resource (usage: make import RESOURCE=aws_db_instance.main ID=my-db)
	@if [ -z "$(RESOURCE)" ] || [ -z "$(ID)" ]; then \
		echo "$(RED)Error: RESOURCE and ID parameters required$(NC)"; \
		echo "Usage: make import RESOURCE=aws_db_instance.main ID=my-db"; \
		exit 1; \
	fi
	@tofu import $(RESOURCE) $(ID)

refresh: ## Refresh OpenTofu state
	@echo "$(YELLOW)Refreshing OpenTofu state...$(NC)"
	@tofu refresh
	@echo "$(GREEN)✓ State refreshed$(NC)"

unlock: ## Force unlock OpenTofu state (use with caution)
	@if [ -z "$(LOCK_ID)" ]; then \
		echo "$(RED)Error: LOCK_ID parameter required$(NC)"; \
		echo "Usage: make unlock LOCK_ID=<lock-id>"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Force unlocking state...$(NC)"
	@tofu force-unlock $(LOCK_ID)

taint: ## Mark resource for recreation (usage: make taint RESOURCE=aws_lambda_function.ingest)
	@if [ -z "$(RESOURCE)" ]; then \
		echo "$(RED)Error: RESOURCE parameter required$(NC)"; \
		echo "Usage: make taint RESOURCE=aws_lambda_function.ingest"; \
		exit 1; \
	fi
	@tofu taint $(RESOURCE)

untaint: ## Remove taint from resource (usage: make untaint RESOURCE=aws_lambda_function.ingest)
	@if [ -z "$(RESOURCE)" ]; then \
		echo "$(RED)Error: RESOURCE parameter required$(NC)"; \
		echo "Usage: make untaint RESOURCE=aws_lambda_function.ingest"; \
		exit 1; \
	fi
	@tofu untaint $(RESOURCE)

info: ## Display project information
	@echo "$(BLUE)=== CIOT Oil Detection Project - Infrastructure ===$(NC)"
	@echo ""
	@echo "$(YELLOW)OpenTofu Version:$(NC)"
	@tofu version | head -n 1 || echo "  Not installed"
	@echo ""
	@echo "$(YELLOW)AWS Region:$(NC) $(REGION)"
	@echo ""
	@echo "$(YELLOW)Environment:$(NC) $(ENVIRONMENT)"
	@echo ""
	@echo "$(YELLOW)Key Resources:$(NC)"
	@echo "  - Lambda Function: buoy-data-ingest-$(ENVIRONMENT)"
	@echo "  - API Gateway: oil-data-ingest-api-$(ENVIRONMENT)"
	@echo "  - RDS Database: ciot-db-$(ENVIRONMENT)"
	@echo "  - S3 Bucket: ciot-buoy-data-$(ENVIRONMENT)-test"
	@echo "  - VPC: ciot-vpc-$(ENVIRONMENT)"
	@echo "  - ECS Cluster: ciot-cluster-$(ENVIRONMENT)"
	@echo "  - Backend Service: ciot-backend-service-$(ENVIRONMENT)"
	@echo "  - Frontend Service: ciot-frontend-service-$(ENVIRONMENT)"
	@echo ""
	@echo "$(YELLOW)Key Infrastructure Outputs:$(NC)"
	@FRONTEND_URL=$$(tofu output -raw frontend_url 2>/dev/null) && \
	if [ -n "$$FRONTEND_URL" ]; then \
		echo "  - Frontend URL: $$FRONTEND_URL"; \
	else \
		echo "  - Frontend URL: Not available"; \
	fi
	@BACKEND_URL=$$(tofu output -raw backend_api_url 2>/dev/null) && \
	if [ -n "$$BACKEND_URL" ]; then \
		echo "  - Backend API URL: $$BACKEND_URL"; \
	else \
		echo "  - Backend API URL: Not available"; \
	fi
	@CLUSTER_NAME=$$(tofu output -raw ecs_cluster_name 2>/dev/null) && \
	if [ -n "$$CLUSTER_NAME" ]; then \
		echo "  - ECS Cluster Name: $$CLUSTER_NAME"; \
	else \
		echo "  - ECS Cluster Name: Not available"; \
	fi
	@ALB_DNS=$$(tofu output -raw alb_dns_name 2>/dev/null) && \
	if [ -n "$$ALB_DNS" ]; then \
		echo "  - ALB DNS Name: $$ALB_DNS"; \
	else \
		echo "  - ALB DNS Name: Not available"; \
	fi
	@API_GATEWAY=$$(tofu output -raw ingest_api_url 2>/dev/null) && \
	if [ -n "$$API_GATEWAY" ]; then \
		echo "  - API Gateway URL: $$API_GATEWAY"; \
	else \
		echo "  - API Gateway URL: Not available"; \
	fi
	@RDS_ENDPOINT=$$(tofu output -raw rds_endpoint 2>/dev/null) && \
	if [ -n "$$RDS_ENDPOINT" ]; then \
		echo "  - RDS Endpoint: $$RDS_ENDPOINT"; \
	else \
		echo "  - RDS Endpoint: Not available"; \
	fi
	@echo ""
	@echo "$(YELLOW)Secrets:$(NC)"
	@echo "  - RDS Credentials: ciot-rds-credentials"
	@echo ""
	@echo "For more commands, run: make help"

backup-state: ## Backup OpenTofu state file
	@echo "$(YELLOW)Backing up OpenTofu state...$(NC)"
	@cp terraform.tfstate terraform.tfstate.backup.$$(date +%Y%m%d-%H%M%S) 2>/dev/null || \
	echo "$(YELLOW)⚠ No state file found to backup$(NC)"
	@echo "$(GREEN)✓ State backed up$(NC)"

test-api: ## Test the API Gateway endpoint
	@echo "$(YELLOW)Testing API Gateway endpoint...$(NC)"
	@API_URL=$$(tofu output -raw ingest_api_url 2>/dev/null) && \
	if [ -n "$$API_URL" ]; then \
		echo "$(BLUE)Testing: $$API_URL/ingest$(NC)"; \
		curl -X POST "$$API_URL/ingest" \
			-H "Content-Type: application/json" \
			-d '{"buoy_id":"test","coordinates":{"lat":1.35,"lon":103.82},"sensor_data":{"oil_detected":false}}' \
			-w "\n$(YELLOW)Status: %{http_code}\n" || \
		echo "$(RED)✗ Request failed$(NC)"; \
	else \
		echo "$(RED)✗ API Gateway not deployed$(NC)"; \
	fi

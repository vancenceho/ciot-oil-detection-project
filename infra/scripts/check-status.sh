#!/bin/bash

# CIOT Oil Detection Infrastructure Status Checker
# Checks the status of all deployed services

set -e

echo "======================================"
echo "CIOT Infrastructure Status Check"
echo "======================================"
echo ""
date
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get environment (default to dev)
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-ap-southeast-1}"

# Function to check status
check_status() {
    local actual="$1"
    local expected="$2"
    local service="$3"
    if [ "$actual" == "$expected" ]; then
        echo -e "${GREEN}✓${NC} $service: $actual"
        return 0
    else
        echo -e "${RED}✗${NC} $service: $actual (expected: $expected)"
        return 1
    fi
}

# Function to show info
show_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

# Track overall status
ALL_GOOD=0

# 1. RDS PostgreSQL Database
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "1. RDS PostgreSQL Database"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
RDS_IDENTIFIER="ciot-db-${ENVIRONMENT}"
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$REGION" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if check_status "$RDS_STATUS" "available" "Status"; then
    RDS_ENDPOINT=$(aws rds describe-db-instances \
      --db-instance-identifier "$RDS_IDENTIFIER" \
      --region "$REGION" \
      --query 'DBInstances[0].Endpoint.Address' \
      --output text 2>/dev/null)
    show_info "Endpoint: $RDS_ENDPOINT"
    
    RDS_PORT=$(aws rds describe-db-instances \
      --db-instance-identifier "$RDS_IDENTIFIER" \
      --region "$REGION" \
      --query 'DBInstances[0].Endpoint.Port' \
      --output text 2>/dev/null)
    show_info "Port: $RDS_PORT"
    
    RDS_ENGINE=$(aws rds describe-db-instances \
      --db-instance-identifier "$RDS_IDENTIFIER" \
      --region "$REGION" \
      --query 'DBInstances[0].EngineVersion' \
      --output text 2>/dev/null)
    show_info "Engine: PostgreSQL $RDS_ENGINE"
    
    RDS_CLASS=$(aws rds describe-db-instances \
      --db-instance-identifier "$RDS_IDENTIFIER" \
      --region "$REGION" \
      --query 'DBInstances[0].DBInstanceClass' \
      --output text 2>/dev/null)
    show_info "Instance Class: $RDS_CLASS"
else
    ALL_GOOD=1
fi
echo ""

# 2. Lambda Function
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "2. Lambda Function"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
LAMBDA_NAME="buoy-data-ingest-${ENVIRONMENT}"
LAMBDA_STATE=$(aws lambda get-function \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" \
  --query 'Configuration.State' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$LAMBDA_STATE" == "NOT_FOUND" ]; then
    echo -e "${YELLOW}⚠${NC} State: NOT_DEPLOYED"
    show_info "Lambda function not found. Run 'terraform apply' to deploy."
    ALL_GOOD=1
elif check_status "$LAMBDA_STATE" "Active" "State"; then
    LAMBDA_RUNTIME=$(aws lambda get-function \
      --function-name "$LAMBDA_NAME" \
      --region "$REGION" \
      --query 'Configuration.Runtime' \
      --output text 2>/dev/null)
    show_info "Runtime: $LAMBDA_RUNTIME"
    
    LAMBDA_UPDATED=$(aws lambda get-function \
      --function-name "$LAMBDA_NAME" \
      --region "$REGION" \
      --query 'Configuration.LastModified' \
      --output text 2>/dev/null)
    show_info "Last updated: $LAMBDA_UPDATED"
    
    # Check invocations in last hour
    # Use macOS-compatible date command (-v-1H for 1 hour ago)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        START_TIME=$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)
    else
        START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
    fi
    LAMBDA_INVOCATIONS=$(aws cloudwatch get-metric-statistics \
      --namespace AWS/Lambda \
      --metric-name Invocations \
      --dimensions Name=FunctionName,Value="$LAMBDA_NAME" \
      --start-time "$START_TIME" \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 3600 \
      --statistics Sum \
      --region "$REGION" \
      --query 'Datapoints[0].Sum' \
      --output text 2>/dev/null || echo "0")
    
    if [ "$LAMBDA_INVOCATIONS" == "None" ] || [ -z "$LAMBDA_INVOCATIONS" ]; then
        LAMBDA_INVOCATIONS="0"
    fi
    show_info "Invocations (last hour): $LAMBDA_INVOCATIONS"
    
    # Check errors
    # Use macOS-compatible date command (-v-1H for 1 hour ago)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        START_TIME=$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)
    else
        START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
    fi
    LAMBDA_ERRORS=$(aws cloudwatch get-metric-statistics \
      --namespace AWS/Lambda \
      --metric-name Errors \
      --dimensions Name=FunctionName,Value="$LAMBDA_NAME" \
      --start-time "$START_TIME" \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 3600 \
      --statistics Sum \
      --region "$REGION" \
      --query 'Datapoints[0].Sum' \
      --output text 2>/dev/null || echo "0")
    
    if [ "$LAMBDA_ERRORS" == "None" ] || [ -z "$LAMBDA_ERRORS" ]; then
        LAMBDA_ERRORS="0"
    fi
    if [ "$LAMBDA_ERRORS" == "0" ] || [ "$LAMBDA_ERRORS" == "0.0" ]; then
        echo -e "${GREEN}✓${NC} Errors (last hour): $LAMBDA_ERRORS"
    else
        echo -e "${RED}✗${NC} Errors (last hour): $LAMBDA_ERRORS"
        ALL_GOOD=1
    fi
else
    echo -e "${YELLOW}⚠${NC} State: $LAMBDA_STATE"
    ALL_GOOD=1
fi
echo ""

# 3. API Gateway
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "3. API Gateway"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
API_NAME="oil-data-ingest-api-${ENVIRONMENT}"
# Temporarily disable set -e for API Gateway check
set +e
API_ID=$(aws apigatewayv2 get-apis \
  --region "$REGION" \
  --query "Items[?Name=='$API_NAME'].ApiId" \
  --output text 2>/dev/null)
API_QUERY_STATUS=$?
set -e

if [ $API_QUERY_STATUS -eq 0 ] && [ -n "$API_ID" ] && [ "$API_ID" != "None" ] && [ "$API_ID" != "" ]; then
    echo -e "${GREEN}✓${NC} API: $API_NAME"
    set +e
    API_ENDPOINT=$(aws apigatewayv2 get-api \
      --region "$REGION" \
      --api-id "$API_ID" \
      --query 'ApiEndpoint' \
      --output text 2>/dev/null)
    set -e
    if [ -n "$API_ENDPOINT" ] && [ "$API_ENDPOINT" != "None" ]; then
        show_info "Endpoint: $API_ENDPOINT/ingest"
    fi
    show_info "Method: POST"
else
    echo -e "${YELLOW}⚠${NC} API: NOT_FOUND"
    show_info "API Gateway not found. Run 'terraform apply' to deploy."
    ALL_GOOD=1
fi
echo ""

# 4. S3 Bucket
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "4. S3 Bucket"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
BUCKET_NAME="ciot-buoy-data-${ENVIRONMENT}-test"
# Check if bucket exists (head-bucket returns 0 if exists, non-zero if not)
# Temporarily disable set -e for this check
set +e
aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null
BUCKET_EXISTS=$?
set -e

if [ $BUCKET_EXISTS -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Bucket: $BUCKET_NAME"
    
    # Count objects in raw/ folder (s3 ls doesn't support --region flag)
    set +e
    RAW_COUNT=$(aws s3 ls "s3://$BUCKET_NAME/raw/" --recursive --summarize 2>/dev/null | grep "Total Objects" | awk '{print $3}' || echo "0")
    set -e
    if [ -z "$RAW_COUNT" ]; then
        RAW_COUNT="0"
    fi
    show_info "Objects in raw/: $RAW_COUNT"
    
    # Check bucket location
    BUCKET_REGION=$(aws s3api get-bucket-location \
      --bucket "$BUCKET_NAME" \
      --query 'LocationConstraint' \
      --output text 2>/dev/null || echo "$REGION")
    if [ "$BUCKET_REGION" == "None" ] || [ -z "$BUCKET_REGION" ]; then
        BUCKET_REGION="us-east-1"
    fi
    show_info "Region: $BUCKET_REGION"
else
    echo -e "${RED}✗${NC} Bucket: NOT_FOUND"
    ALL_GOOD=1
fi
echo ""

# 5. Secrets Manager
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "5. Secrets Manager"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
SECRET_NAME="ciot-rds-credentials"
SECRET_EXISTS=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query 'Name' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$SECRET_EXISTS" == "$SECRET_NAME" ]; then
    echo -e "${GREEN}✓${NC} Secret: $SECRET_NAME"
    SECRET_ARN=$(aws secretsmanager describe-secret \
      --secret-id "$SECRET_NAME" \
      --region "$REGION" \
      --query 'ARN' \
      --output text 2>/dev/null)
    show_info "ARN: $SECRET_ARN"
else
    echo -e "${YELLOW}⚠${NC} Secret: NOT_FOUND"
    show_info "Run './scripts/setup-secrets.sh' to create the secret."
    ALL_GOOD=1
fi
echo ""

# 6. VPC & Networking
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "6. VPC & Networking"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
VPC_NAME="ciot-vpc-${ENVIRONMENT}"
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$VPC_NAME" \
  --region "$REGION" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "")

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    echo -e "${GREEN}✓${NC} VPC: $VPC_ID"
    VPC_CIDR=$(aws ec2 describe-vpcs \
      --vpc-ids "$VPC_ID" \
      --region "$REGION" \
      --query 'Vpcs[0].CidrBlock' \
      --output text 2>/dev/null)
    show_info "CIDR: $VPC_CIDR"
    
    # Check security group
    SG_NAME="ciot-rds-sg-${ENVIRONMENT}"
    SG_ID=$(aws ec2 describe-security-groups \
      --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
      --region "$REGION" \
      --query 'SecurityGroups[0].GroupId' \
      --output text 2>/dev/null || echo "")
    
    if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        echo -e "${GREEN}✓${NC} Security Group: $SG_ID ($SG_NAME)"
        
        # Check if port 5432 is open
        SG_PORT=$(aws ec2 describe-security-groups \
          --group-ids "$SG_ID" \
          --region "$REGION" \
          --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`].FromPort' \
          --output text 2>/dev/null || echo "")
        
        if [ "$SG_PORT" == "5432" ]; then
            echo -e "${GREEN}✓${NC} Port 5432: Open"
        else
            echo -e "${YELLOW}⚠${NC} Port 5432: Not configured"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Security Group: NOT_FOUND"
    fi
    
    # Check subnets
    SUBNET_COUNT=$(aws ec2 describe-subnets \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=ciot-private-subnet-${ENVIRONMENT}*" \
      --region "$REGION" \
      --query 'length(Subnets)' \
      --output text 2>/dev/null || echo "0")
    show_info "Private Subnets: $SUBNET_COUNT"
else
    echo -e "${RED}✗${NC} VPC: Not found"
    ALL_GOOD=1
fi
echo ""

# 7. Port Configuration
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "7. Port Configuration"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$RDS_STATUS" == "available" ]; then
    if [ "$RDS_PORT" == "5432" ] && [ "$SG_PORT" == "5432" ]; then
        echo -e "${GREEN}✓${NC} Port configuration: All components use 5432"
        show_info "RDS: $RDS_PORT | Security Group: $SG_PORT"
    else
        echo -e "${RED}✗${NC} Port mismatch detected!"
        show_info "RDS: $RDS_PORT | Security Group: $SG_PORT"
        ALL_GOOD=1
    fi
else
    echo -e "${YELLOW}⚠${NC} Cannot verify port configuration (RDS not available)"
fi
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Summary"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $ALL_GOOD -eq 0 ]; then
    echo -e "${GREEN}✓ All deployed services are running normally!${NC}"
    echo ""
    echo "Next steps:"
    echo "  • Test API: curl -X POST <API_URL>/ingest -H 'Content-Type: application/json' -d '{\"buoy_id\":\"test\",\"coordinates\":{\"lat\":1.35,\"lon\":103.82},\"sensor_data\":{\"oil_detected\":false}}'"
    echo "  • View Lambda logs: aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
    echo "  • Check S3 data: aws s3 ls s3://$BUCKET_NAME/raw/ --recursive --region $REGION"
    echo "  • Monitor metrics: https://console.aws.amazon.com/cloudwatch/"
else
    echo -e "${YELLOW}⚠ Some services need attention${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  • Check Lambda logs: aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
    echo "  • Review deployment: cd infra/ && terraform plan"
    echo "  • Verify secrets: ./scripts/setup-secrets.sh"
    echo "  • Check RDS status: aws rds describe-db-instances --db-instance-identifier $RDS_IDENTIFIER --region $REGION"
fi
echo ""
echo "======================================"
echo "Status check completed at $(date)"
echo "======================================"

exit $ALL_GOOD


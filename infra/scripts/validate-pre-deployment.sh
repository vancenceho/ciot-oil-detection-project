#!/bin/bash

# Pre-deployment validation script for CIOT Oil Detection Project

# This script checks prerequisites and sets up required AWS resources

# before running tofu apply

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=============================================="
echo "CIOT Oil Detection Project - Pre-Deployment Validation"
echo "=============================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track if any checks fail
CHECKS_FAILED=0

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    CHECKS_FAILED=1
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo "  $1"
}

echo "Step 1: Checking prerequisites..."
echo "-------------------------------------------"

# Check if AWS CLI is installed
if command -v aws &> /dev/null; then
    print_success "AWS CLI is installed"
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1)
    print_info "$AWS_VERSION"
else
    print_error "AWS CLI is not installed"
    print_info "Install: https://aws.amazon.com/cli/"
fi

# Check if OpenTofu/Terraform is installed
if command -v tofu &> /dev/null; then
    print_success "OpenTofu is installed"
    TF_VERSION=$(tofu version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || tofu version | head -n1)
    print_info "$TF_VERSION"
elif command -v terraform &> /dev/null; then
    print_warning "Terraform is installed (consider using OpenTofu)"
    TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || terraform version | head -n1)
    print_info "$TF_VERSION"
else
    print_error "OpenTofu/Terraform is not installed"
    print_info "Install: https://opentofu.org/docs/intro/install/"
fi

# Check if jq is installed (for JSON parsing)
if command -v jq &> /dev/null; then
    print_success "jq is installed"
else
    print_warning "jq is not installed (optional, but recommended for JSON parsing)"
    print_info "Install: brew install jq (macOS) or apt-get install jq (Linux)"
fi

echo ""
echo "Step 2: Validating AWS credentials..."
echo "-------------------------------------------"

# Check if AWS credentials are configured
if aws sts get-caller-identity &> /dev/null; then
    print_success "AWS credentials are configured"
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
    print_info "Account ID: $AWS_ACCOUNT"
    print_info "Identity: $AWS_USER"
else
    print_error "AWS credentials are not configured"
    print_info "Run: aws configure"
    print_info "Or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables"
fi

echo ""
echo "Step 3: Checking RDS credentials secret..."
echo "-------------------------------------------"

# Check if RDS credentials secret exists
SECRET_NAME="ciot-rds-credentials"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &> /dev/null; then
    print_success "RDS credentials secret exists in AWS Secrets Manager"
    # Try to get the secret value to verify it's valid JSON
    if SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text 2>/dev/null); then
        if command -v jq &> /dev/null; then
            if echo "$SECRET_VALUE" | jq -e '.username and .password' &> /dev/null 2>&1; then
                USERNAME=$(echo "$SECRET_VALUE" | jq -r '.username' 2>/dev/null)
                print_success "Secret contains valid username and password"
                print_info "Username: $USERNAME"
            else
                print_error "Secret exists but does not contain 'username' and 'password' fields"
                print_info "Expected format: {\"username\":\"...\",\"password\":\"...\"}"
            fi
        else
            print_warning "Cannot validate secret format (jq not installed)"
            print_info "Secret exists: $SECRET_NAME"
        fi
    fi
else
    print_error "RDS credentials secret NOT found in AWS Secrets Manager"
    echo ""
    print_info "You must create this secret before running tofu apply."
    print_info "Run the following command:"
    echo ""
    echo -e "${YELLOW}./scripts/setup-secrets.sh${NC}"
    echo ""
    print_warning "Or manually create the secret using AWS CLI:"
    echo ""
    echo -e "${YELLOW}aws secretsmanager create-secret \\${NC}"
    echo -e "${YELLOW}  --name $SECRET_NAME \\${NC}"
    echo -e "${YELLOW}  --secret-string '{\"username\":\"ciotadmin\",\"password\":\"CHANGE_THIS_PASSWORD\"}'${NC}"
    echo ""
    print_warning "Remember to change the password to a secure one!"
    echo ""
fi

echo ""
echo "Step 4: Checking Terraform/OpenTofu state..."
echo "-------------------------------------------"

cd "$INFRA_DIR"

# Check if Terraform/OpenTofu has been initialized
if [ -d ".terraform" ]; then
    print_success "Terraform/OpenTofu has been initialized"
else
    print_warning "Terraform/OpenTofu has not been initialized"
    print_info "Run: tofu init (or terraform init)"
fi

# Check if lambda_ingest.zip exists (required for Lambda function)
LAMBDA_FILE="scripts/lambda_ingest.zip"
if [ -f "$LAMBDA_FILE" ]; then
    print_success "lambda_ingest.zip exists"
    LAMBDA_SIZE=$(du -h "$LAMBDA_FILE" | cut -f1)
    print_info "Size: $LAMBDA_SIZE"
else
    print_warning "lambda_ingest.zip does not exist"
    print_info "Lambda function deployment will fail without this file"
    print_info "Location expected: $LAMBDA_FILE"
fi

echo ""
echo "Step 5: Validating Terraform/OpenTofu configuration..."
echo "-------------------------------------------"

# Run tofu/terraform validate (only if initialized)
if [ -d ".terraform" ]; then
    if command -v tofu &> /dev/null; then
        if tofu validate &> /dev/null; then
            print_success "OpenTofu configuration is valid"
        else
            print_error "OpenTofu configuration has errors"
            echo ""
            tofu validate
            echo ""
        fi
    elif command -v terraform &> /dev/null; then
        if terraform validate &> /dev/null; then
            print_success "Terraform configuration is valid"
        else
            print_error "Terraform configuration has errors"
            echo ""
            terraform validate
            echo ""
        fi
    fi
else
    print_warning "Skipping validation (run 'tofu init' or 'terraform init' first)"
fi

echo ""
echo "=============================================="
echo "Summary"
echo "=============================================="
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "You are ready to deploy. Run the following commands:"
    echo ""
    echo "  cd $INFRA_DIR"
    if [ ! -d ".terraform" ]; then
        echo "  tofu init                    # Initialize Terraform/OpenTofu"
    fi
    echo "  ./scripts/setup-secrets.sh     # Create RDS credentials secret (if not done)"
    echo "  make plan                      # Review the deployment plan"
    echo "  make apply                     # Deploy to AWS"
    echo ""
else
    echo -e "${RED}Some checks failed!${NC}"
    echo ""
    echo "Please resolve the issues above before running tofu apply."
    echo ""
    exit 1
fi

echo "=============================================="
echo ""


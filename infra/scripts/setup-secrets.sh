#!/bin/bash
# Setup script to create RDS credentials in AWS Secrets Manager
#
# Run this BEFORE terraform apply

set -e

SECRET_NAME="ciot-rds-credentials"
DB_USERNAME="ciotadmin"

echo -e "\033[36m=== CIOT RDS Credentials Setup ===\033[0m"
echo ""

# Check if secret already exists
echo "Checking if secret already exists..."
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" 2>/dev/null; then
    echo -e "\033[33mSecret '$SECRET_NAME' already exists.\033[0m"
    echo ""
    read -p "Do you want to update the password? (y/N): " UPDATE_SECRET
    if [[ "$UPDATE_SECRET" != "y" && "$UPDATE_SECRET" != "Y" ]]; then
        echo "Keeping existing secret."
        exit 0
    fi
    
    # Generate new password
    DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
    
    # Update existing secret
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "{\"username\":\"$DB_USERNAME\",\"password\":\"$DB_PASSWORD\"}"
    
    echo -e "\033[32m✓ Secret updated!\033[0m"
else
    echo "Creating new secret..."
    
    # Generate a secure random password (20 chars, alphanumeric)
    DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
    
    # Create the secret
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "RDS PostgreSQL credentials for CIOT project" \
        --secret-string "{\"username\":\"$DB_USERNAME\",\"password\":\"$DB_PASSWORD\"}"
    
    echo -e "\033[32m✓ Secret created!\033[0m"
fi

echo ""
echo -e "\033[36mSecret Details:\033[0m"
echo "  Name: $SECRET_NAME"
echo "  Username: $DB_USERNAME"
echo "  Password: (stored securely in Secrets Manager)"
echo ""
echo -e "\033[36mNext steps:\033[0m"
echo "  1. Run: tofu apply (or terraform apply)"
echo "  2. The Glue connection will use these credentials directly"
echo ""


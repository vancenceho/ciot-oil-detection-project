.PHONY: validate plan apply destroy setup-secrets check-status pre-deployment

validate: 
	tofu validate

plan: 
	tofu plan

apply: 
	tofu apply

destroy:
	tofu destroy

setup-secrets:
	chmod +x scripts/setup-secrets.sh
	./scripts/setup-secrets.sh

check-status:
	chmod +x scripts/check-status.sh
	./scripts/check-status.sh

pre-deployment:
	chmod +x scripts/validate-pre-deployment.sh
	./scripts/validate-pre-deployment.sh
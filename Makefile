# Clickstream Analytics — Makefile
# All targets run against AWS profile `training` in eu-central-1.

export AWS_PROFILE ?= training
TF_DIR := terraform

.PHONY: help init plan apply deploy destroy fmt validate lint test demo

help:
	@echo "Targets:"
	@echo "  init      terraform init"
	@echo "  plan      terraform plan"
	@echo "  apply     terraform apply (alias: deploy)"
	@echo "  destroy   terraform destroy"
	@echo "  fmt       terraform fmt -recursive"
	@echo "  validate  terraform validate"
	@echo "  lint      ruff check on Python (lambda + simulator)"
	@echo "  test      python -m py_compile on Python"
	@echo "  demo      print the demo steps"

init:
	cd $(TF_DIR) && terraform init

plan: init
	cd $(TF_DIR) && terraform plan

apply deploy: init
	cd $(TF_DIR) && terraform apply

destroy:
	cd $(TF_DIR) && terraform destroy

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

validate: init
	cd $(TF_DIR) && terraform validate

lint:
	ruff check lambda simulator

test:
	python -m py_compile lambda/fraud-detector/handler.py lambda/firehose-transform/handler.py simulator/simulator.py

demo:
	@echo "1. make deploy"
	@echo "2. Confirm the SNS subscription email"
	@echo "3. Run sql/redshift-schema.sql in Redshift Query Editor v2"
	@echo "4. cd simulator && pip install -r requirements.txt"
	@echo "5. python simulator.py --rate 50   (stream name: terraform output stream_name)"
	@echo "6. Trigger fraud: python simulator.py --fraud --user-id attacker_1 --rate 200"
	@echo "7. Watch the CloudWatch dashboard: terraform output dashboard_url"
	@echo "8. make destroy   (when done)"

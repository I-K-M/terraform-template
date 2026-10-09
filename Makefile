.PHONY: offline-check terraform-check scan security-check

offline-check:
	python3 scripts/security_regression.py
	python3 -m unittest discover -s scripts -p 'test_*.py'

terraform-check:
	terraform fmt -check -recursive
	terraform init -backend=false -input=false
	terraform validate -no-color
	terraform test -no-color
	terraform -chdir=bootstrap/state-backend init -backend=false -input=false
	terraform -chdir=bootstrap/state-backend validate -no-color

scan:
	trivy config --severity HIGH,CRITICAL --exit-code 1 .

security-check: offline-check terraform-check scan

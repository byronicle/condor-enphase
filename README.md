# condor-enphase
Grabs data from local Enphase Envoy device, stores it, and creates custom graphs. This version deploys the application to a Google Compute VM by cloning from a Cloud Source Repository.

## Prerequisites
- gcloud CLI authenticated and set to your GCP project
- Terraform v1.5+ installed
- Service account or user with permissions to create Compute Engine resources and Source Repos

## Deployment
```shell
# from workspace root (PowerShell)
cd terraform
terraform init            # initialize backend and providers
terraform plan -var="project_id=<YOUR_PROJECT_ID>" -var="repo_name=<REPO_NAME>" -var="service_account_email=<SA_EMAIL>"
terraform apply -auto-approve -var="project_id=<YOUR_PROJECT_ID>" -var="repo_name=<REPO_NAME>" -var="service_account_email=<SA_EMAIL>"
```

After apply, note the external IP, service account email, and source repo URL from Terraform outputs.

## Recommendations
- Use Cloud Build GitHub App or Cloud Build triggers to automatically mirror GitHub to your Cloud Source Repository
- Store sensitive tokens (e.g., Enphase tokens) in Secret Manager instead of local files
- For production, consider using a Managed Instance Group behind a Load Balancer for high availability
- Leverage GitHub Actions for CI/CD to Terraform for automated infra changes

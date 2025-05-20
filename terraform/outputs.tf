// Root outputs from modules
// removed Artifact Registry output since registry module is no longer used
// URL of the Cloud Source Repository
output "source_repo_url" {
  description = "HTTPS URL of the Cloud Source Repository"
  value       = "https://source.developers.google.com/p/${var.project_id}/r/${var.repo_name}"
}

output "vm_external_ip" {
  description = "External IP of the Enphase VM from infra module"
  value       = module.infra.instance_ip
}
// email of the service account attached to the VM
output "vm_service_account_email" {
  description = "Service account email used by the VM"
  value       = module.infra.service_account_email
}

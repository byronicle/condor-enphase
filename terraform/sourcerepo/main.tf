# Module to provision Cloud Source Repository and service account for VM access
resource "google_cloudbuildv2_repository" "app_repo" {
  project        = var.project_id
  location       = "global"
  repository_id  = var.repo_name
}

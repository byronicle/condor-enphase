# Module to provision Cloud Source Repository and service account for VM access
resource "google_cloudbuild_repository" "app_repo" {
  project       = var.project_id
  location      = "global"
  repository_id = var.repo_name
  remote_uri    = "https://source.developers.google.com/p/${var.project_id}/r/${var.repo_name}"
}

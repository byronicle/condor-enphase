# Module to provision Cloud Source Repository and service account for VM access
resource "google_cloudbuildv2_repository" "app_repo" {
  provider          = google-beta
  name              = var.repo_name
  parent_connection = "projects/${var.project_id}/locations/us-central1/connections/_internal"
  remote_uri        = "https://source.developers.google.com/p/${var.project_id}/r/${var.repo_name}"
}

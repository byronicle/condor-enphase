# Module to provision Cloud Source Repository and service account for VM access
resource "google_sourcerepo_repository" "app_repo" {
  provider = google
  name     = var.repo_name
}

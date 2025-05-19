# This Terraform configuration file provisions a Google Cloud Source Repository
# and a GitHub connection for Google Cloud Build using a personal access token (PAT).

// Create a secret containing the personal access token and grant permissions to the Service Agent
resource "google_secret_manager_secret" "github_token_secret" {
    project = var.project_id
    secret_id = var.secret_id

    replication {
        auto {}
    }
}

resource "google_secret_manager_secret_version" "github_token_secret_version" {
    secret = google_secret_manager_secret.github_token_secret.id
    secret_data = var.github_pat
}

data "google_iam_policy" "serviceagent_secretAccessor" {
    binding {
        role = "roles/secretmanager.secretAccessor"
        members = ["serviceAccount:service-${var.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"]
    }
}

resource "google_secret_manager_secret_iam_policy" "policy" {
  project = google_secret_manager_secret.github_token_secret.project
  secret_id = google_secret_manager_secret.github_token_secret.secret_id
  policy_data = data.google_iam_policy.serviceagent_secretAccessor.policy_data
}

// Create the GitHub connection
resource "google_cloudbuildv2_connection" "my_connection" {
    project = var.project_id
    location = var.region
    name = var.connection_name

    github_config {
        app_installation_id = var.installation_id
        authorizer_credential {
            oauth_token_secret_version = google_secret_manager_secret_version.github_token_secret_version.id
        }
    }
    depends_on = [ google_secret_manager_secret_iam_policy.policy ]
}

// Create the Cloud Source Repository
resource "google_cloudbuildv2_repository" "my_repository" {
      project = var.project_id
      location = var.region
      name = var.repo_name 
      parent_connection = google_cloudbuildv2_connection.my_connection.name
      remote_uri = "URI"
  }

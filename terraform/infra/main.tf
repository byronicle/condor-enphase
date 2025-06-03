module "service_accounts" {
  source = "terraform-google-modules/service-accounts/google"

  project_id = var.project_id
  names      = ["enphase-vm"]
  project_roles = [
    "${var.project_id}=>roles/secretmanager.secretAccessor",
  ]
  display_name = "Enphase VM Service Account"
  description  = "Enphase VM Service Account"
}

resource "google_compute_instance" "enphase" {
  name         = "enphase-vm"
  machine_type = var.machine_type
  tags         = ["http-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-minimal-2404-lts-amd64"
      size  = 30
    }
  }

  network_interface {
    network = "default"
    access_config {} # external IP
  }

  # attach service account for Cloud Source Repository access
  service_account {
    email = module.service_accounts.email["enphase-vm"]
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/source.read_only"
    ]
  }

  # load startup script from external template and interpolate project_id and repo_name
  metadata_startup_script = templatefile(
    "${path.module}/startup.sh.tpl",
    { repo_name = var.github_repo_ssh_url }
  )
}

# GCP Secret Manager secrets for VM application
resource "google_secret_manager_secret" "enphase_local_token" {
  project   = var.project_id
  secret_id = "ENPHASE_LOCAL_TOKEN"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "enphase_local_token_version" {
  secret      = google_secret_manager_secret.enphase_local_token.id
  secret_data = var.enphase_local_token
}

resource "google_secret_manager_secret" "envoy_host" {
  project   = var.project_id
  secret_id = "ENVOY_HOST"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "envoy_host_version" {
  secret      = google_secret_manager_secret.envoy_host.id
  secret_data = var.envoy_host
}

resource "google_secret_manager_secret" "ts_authkey" {
  project   = var.project_id
  secret_id = "TS_AUTHKEY"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "ts_authkey_version" {
  secret      = google_secret_manager_secret.ts_authkey.id
  secret_data = var.ts_authkey
}

resource "google_secret_manager_secret" "influxdb_admin_password" {
  project   = var.project_id
  secret_id = "influxdb_admin_password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "influxdb_admin_password_version" {
  secret      = google_secret_manager_secret.influxdb_admin_password.id
  secret_data = var.influxdb_admin_password
}

resource "google_secret_manager_secret" "influxdb_admin_token" {
  project   = var.project_id
  secret_id = "influxdb_admin_token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "influxdb_admin_token_version" {
  secret      = google_secret_manager_secret.influxdb_admin_token.id
  secret_data = var.influxdb_admin_token
}

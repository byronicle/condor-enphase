module "service_accounts" {
  source  = "terraform-google-modules/service-accounts/google"

  project_id    = var.project_id
  names         = ["enphase-vm"]
  project_roles = [
    "${var.project_id}=>roles/source.reader"
  ]
  display_name  = "GitHub Actions Service Account"
  description   = "GitHub Actions Service Account"
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
    network       = "default"
    access_config {}  # external IP
  }

  # attach service account for Cloud Source Repository access
  service_account {
    email  = module.service_accounts.email["enphase-vm"]
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/source.read_only"
    ]
  }

  # load startup script from external template and interpolate project_id and repo_name
  metadata_startup_script = templatefile(
    "${path.module}/startup.sh.tpl",
    { project_id = var.project_id,
      repo_name  = var.repo_name }
  )
}

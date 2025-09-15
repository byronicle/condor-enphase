# GKE Cluster Configuration

# GKE Cluster - Zonal Standard (free tier eligible)
resource "google_container_cluster" "enphase_cluster" {
  name     = var.cluster_name
  location = var.zone

  # Minimal configuration for free tier
  initial_node_count       = 1
  remove_default_node_pool = true

  # Network configuration
  network    = "default"
  subnetwork = "default"

  # Enable basic features
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  # Disable expensive features
  addons_config {
    network_policy_config {
      disabled = true
    }
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = true
    }
  }

  # Enable workload identity for secure secret access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Security configuration
  private_cluster_config {
    enable_private_nodes    = false # Keep simple for free tier
    enable_private_endpoint = false
  }

  # Resource labels
  resource_labels = {
    environment = "production"
    application = "enphase"
  }
}

# Node pool configuration
resource "google_container_node_pool" "enphase_nodes" {
  name     = "${var.cluster_name}-nodes-v2"
  location = var.zone
  cluster  = google_container_cluster.enphase_cluster.name

  # Start with minimal nodes for cost
  initial_node_count = 1

  # Auto-scaling configuration (optional)
  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Node configuration
  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size
    disk_type    = "pd-standard"

    # Use spot instances for cost savings (optional)
    spot = var.use_spot_instances

    # Required scopes for workload
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    # Security and resource configuration
    service_account = google_service_account.gke_node_sa.email

    # Enable workload identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Resource labels
    labels = {
      environment = "production"
      application = "enphase"
    }

    # Taints for dedicated workload (optional)
    # taint {
    #   key    = "enphase-only"
    #   value  = "true"
    #   effect = "NO_SCHEDULE"
    # }
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Service account for GKE nodes
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node Service Account for ${var.cluster_name}"
  description  = "Service account for GKE nodes in ${var.cluster_name} cluster"
}

# IAM binding for node service account
resource "google_project_iam_member" "gke_node_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    # Needed to pull images from gcr.io
    "roles/storage.objectViewer",
    # If image is in Artifact Registry (future-proof)
    "roles/artifactregistry.reader"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# Wait for cluster to be fully ready
resource "time_sleep" "wait_for_cluster" {
  depends_on = [google_container_node_pool.enphase_nodes]

  create_duration = "30s"
}
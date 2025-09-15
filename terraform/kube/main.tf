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

# Tailscale operator namespace
resource "kubernetes_namespace" "tailscale" {
  metadata {
    name = "tailscale"
  }

  depends_on = [
    google_container_node_pool.enphase_nodes,
    time_sleep.wait_for_cluster
  ]
}

# Tailscale operator OAuth secret - managed by Helm
# The Helm chart will create this secret automatically

# Install Tailscale operator using Helm
resource "helm_release" "tailscale_operator" {
  name       = "tailscale-operator"
  repository = "https://pkgs.tailscale.com/helmcharts"
  chart      = "tailscale-operator"
  namespace  = kubernetes_namespace.tailscale.metadata[0].name

  set {
    name  = "oauth.clientId"
    value = var.tailscale_oauth_client_id
  }

  set {
    name  = "oauth.clientSecret"
    value = var.tailscale_oauth_client_secret
  }

  set {
    name  = "operatorConfig.defaultTags"
    value = "tag:k8s"
  }

  set {
    name  = "operatorConfig.acceptRoutes"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.tailscale
  ]
}

# ProxyClass to enable accepting subnet routes
resource "kubernetes_manifest" "accept_routes_proxy_class" {
  manifest = {
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "ProxyClass"
    metadata = {
      name = "accept-routes"
    }
    spec = {
      tailscale = {
        acceptRoutes = true
      }
    }
  }

  depends_on = [
    helm_release.tailscale_operator
  ]
}

# Tailscale cluster egress service for home network access behind subnet router
# This creates a Service that exposes your home network device to the cluster
resource "kubernetes_service" "home_network_egress" {
  metadata {
    name      = "home-network"
    namespace = kubernetes_namespace.enphase.metadata[0].name
    annotations = {
      "tailscale.com/tailnet-ip"  = var.envoy_host
      "tailscale.com/proxy-class" = "accept-routes"
    }
  }
  spec {
    external_name = "unused"
    type          = "ExternalName"
  }

  depends_on = [
    helm_release.tailscale_operator,
    kubernetes_namespace.enphase,
    kubernetes_manifest.accept_routes_proxy_class
  ]
}

# Kubernetes namespace
resource "kubernetes_namespace" "enphase" {
  metadata {
    name = var.namespace
  }

  depends_on = [
    google_container_node_pool.enphase_nodes,
    time_sleep.wait_for_cluster
  ]
}







# Kubernetes Secrets
resource "kubernetes_secret" "enphase_secrets" {
  metadata {
    name      = "enphase-secrets"
    namespace = kubernetes_namespace.enphase.metadata[0].name
  }

  data = {
    ENPHASE_LOCAL_TOKEN     = var.enphase_local_token
    ENVOY_HOST              = var.envoy_host
    TS_AUTHKEY              = var.ts_authkey
    influxdb_admin_password = var.influxdb_admin_password
    influxdb_admin_token    = var.influxdb_admin_token
  }

  type = "Opaque"

  lifecycle {
    ignore_changes = [data]
  }
}

# PersistentVolumeClaims
resource "kubernetes_persistent_volume_claim" "influxdb_data" {
  metadata {
    name      = "influxdb-data"
    namespace = kubernetes_namespace.enphase.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.influxdb_storage_size
      }
    }
    storage_class_name = var.storage_class
  }

  depends_on = [
    google_container_node_pool.enphase_nodes
  ]

  timeouts {
    create = "10m"
  }
}

resource "kubernetes_persistent_volume_claim" "grafana_data" {
  metadata {
    name      = "grafana-data"
    namespace = kubernetes_namespace.enphase.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.grafana_storage_size
      }
    }
    storage_class_name = var.storage_class
  }

  depends_on = [
    google_container_node_pool.enphase_nodes
  ]

  timeouts {
    create = "10m"
  }
}


# Note: token_volume is now handled as emptyDir in pod specs
# since ReadWriteMany is not supported by GKE standard storage classes

# ConfigMaps
resource "kubernetes_config_map" "influxdb_init" {
  metadata {
    name      = "influxdb-init"
    namespace = kubernetes_namespace.enphase.metadata[0].name
  }

  # You'll need to add your init scripts here
  # data = {
  #   "init.sh" = file("${path.module}/init/init.sh")
  # }
}

# InfluxDB Deployment
resource "kubernetes_deployment" "influxdb" {
  metadata {
    name      = "influxdb"
    namespace = kubernetes_namespace.enphase.metadata[0].name
    labels = {
      app = "influxdb"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "influxdb"
      }
    }

    template {
      metadata {
        labels = {
          app = "influxdb"
        }
      }

      spec {
        container {
          image = "influxdb:2.7-alpine"
          name  = "influxdb"

          port {
            container_port = 8086
          }

          env {
            name  = "DOCKER_INFLUXDB_INIT_MODE"
            value = "setup"
          }

          env {
            name  = "DOCKER_INFLUXDB_INIT_USERNAME"
            value = "admin"
          }

          env {
            name  = "DOCKER_INFLUXDB_INIT_ORG"
            value = "enphase"
          }

          env {
            name  = "DOCKER_INFLUXDB_INIT_BUCKET"
            value = "solar"
          }

          env {
            name = "DOCKER_INFLUXDB_INIT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.enphase_secrets.metadata[0].name
                key  = "influxdb_admin_password"
              }
            }
          }

          env {
            name = "DOCKER_INFLUXDB_INIT_ADMIN_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.enphase_secrets.metadata[0].name
                key  = "influxdb_admin_token"
              }
            }
          }

          volume_mount {
            name       = "influxdb-data"
            mount_path = "/var/lib/influxdb2"
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "influx ping --host http://localhost:8086"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 5
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "influx ping --host http://localhost:8086"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 5
          }
        }

        volume {
          name = "influxdb-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.influxdb_data.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_persistent_volume_claim.influxdb_data,
    time_sleep.wait_for_cluster
  ]
}

# InfluxDB Service
resource "kubernetes_service" "influxdb" {
  metadata {
    name      = "influxdb"
    namespace = kubernetes_namespace.enphase.metadata[0].name
  }
  spec {
    selector = {
      app = kubernetes_deployment.influxdb.metadata[0].labels.app
    }
    port {
      port        = 8086
      target_port = 8086
    }
  }
}

# Grafana Deployment with Tailscale sidecar
resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.enphase.metadata[0].name
    labels = {
      app = "grafana"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        # Ensure the mounted PVC gets appropriate ownership for grafana (uid 472)
        security_context {
          fs_group = 472
        }

        init_container {
          name  = "wait-for-influxdb"
          image = "busybox:1.35"
          command = [
            "sh",
            "-c",
            "until nc -z influxdb 8086; do echo waiting for influxdb; sleep 2; done;"
          ]
        }

        # Fix permissions on first start (PVC mounts root:root by default on GKE)
        init_container {
          name  = "fix-permissions"
          image = "busybox:1.35"
          command = [
            "sh",
            "-c",
            "chown -R 472:472 /var/lib/grafana || true"
          ]
          security_context {
            run_as_user = 0
          }
          volume_mount {
            name       = "grafana-data"
            mount_path = "/var/lib/grafana"
          }
        }

        container {
          image = "grafana/grafana-oss:12.0.0"
          name  = "grafana"

          port {
            container_port = 3000
          }

          volume_mount {
            name       = "grafana-data"
            mount_path = "/var/lib/grafana"
          }

          security_context {
            run_as_user     = 472
            run_as_group    = 472
            run_as_non_root = true
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }


        volume {
          name = "grafana-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana_data.metadata[0].name
          }
        }

      }
    }
  }

  depends_on = [
    kubernetes_persistent_volume_claim.grafana_data,
    kubernetes_service.influxdb,
    time_sleep.wait_for_cluster
  ]

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Grafana Service with Tailscale ingress
resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.enphase.metadata[0].name
    annotations = {
      "tailscale.com/expose"   = "true"
      "tailscale.com/hostname" = "grafana-k8s-cluster"
      "tailscale.com/tags"     = "tag:k8s"
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.grafana.metadata[0].labels.app
    }
    port {
      port        = 3000
      target_port = 3000
    }
    type = "ClusterIP"
  }

  depends_on = [
    helm_release.tailscale_operator
  ]
}

# Ingestor Deployment
resource "kubernetes_deployment" "ingestor" {
  metadata {
    name      = "ingestor"
    namespace = kubernetes_namespace.enphase.metadata[0].name
    labels = {
      app = "ingestor"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ingestor"
      }
    }

    template {
      metadata {
        labels = {
          app = "ingestor"
        }
      }

      spec {
        init_container {
          name  = "wait-for-influxdb"
          image = "busybox:1.35"
          command = [
            "sh",
            "-c",
            "until nc -z influxdb 8086; do echo waiting for influxdb; sleep 2; done;"
          ]
        }


        container {
          image = var.ingestor_image
          name  = "ingestor"

          working_dir = "/app"

          env {
            name  = "INFLUXDB_URL"
            value = "http://influxdb:8086"
          }

          env {
            name  = "INFLUXDB_ORG"
            value = "enphase"
          }

          env {
            name  = "INFLUXDB_BUCKET"
            value = "solar"
          }

          env {
            name = "ENPHASE_LOCAL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.enphase_secrets.metadata[0].name
                key  = "ENPHASE_LOCAL_TOKEN"
              }
            }
          }

          env {
            name  = "ENVOY_HOST"
            value = "home-network.${kubernetes_namespace.enphase.metadata[0].name}.svc.cluster.local"
          }

          env {
            name = "INFLUXDB_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.enphase_secrets.metadata[0].name
                key  = "influxdb_admin_token"
              }
            }
          }

        }


      }
    }
  }

  depends_on = [
    kubernetes_service.influxdb,
    time_sleep.wait_for_cluster
  ]

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# InfluxDB Configuration

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
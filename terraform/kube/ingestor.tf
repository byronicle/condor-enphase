# Ingestor Application Configuration

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
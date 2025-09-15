# Grafana Configuration

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
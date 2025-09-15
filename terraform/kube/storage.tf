# Storage Configuration

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
# Secrets and Configuration

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
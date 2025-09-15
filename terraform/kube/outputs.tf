# Cluster information
output "cluster_name" {
  value       = google_container_cluster.enphase_cluster.name
  description = "Name of the GKE cluster"
}

output "cluster_endpoint" {
  value       = google_container_cluster.enphase_cluster.endpoint
  description = "GKE cluster endpoint"
}

output "cluster_location" {
  value       = google_container_cluster.enphase_cluster.location
  description = "GKE cluster location"
}

output "node_service_account" {
  value       = google_service_account.gke_node_sa.email
  description = "Service account used by GKE nodes"
}

# Kubernetes resources
output "namespace" {
  value       = kubernetes_namespace.enphase.metadata[0].name
  description = "Kubernetes namespace for Enphase resources"
}

output "influxdb_service_name" {
  value       = kubernetes_service.influxdb.metadata[0].name
  description = "InfluxDB service name for internal connectivity"
}

output "grafana_service_name" {
  value       = kubernetes_service.grafana.metadata[0].name
  description = "Grafana service name"
}

output "grafana_tailscale_access" {
  value       = "Access Grafana via Tailscale through the cluster egress"
  description = "Access Grafana through Tailscale using the cluster egress configuration"
}

output "secret_names" {
  value = {
    enphase_secrets = kubernetes_secret.enphase_secrets.metadata[0].name
  }
  description = "Names of Kubernetes secrets created"
}

output "pvc_names" {
  value = {
    influxdb_data = kubernetes_persistent_volume_claim.influxdb_data.metadata[0].name
    grafana_data  = kubernetes_persistent_volume_claim.grafana_data.metadata[0].name
  }
  description = "Names of persistent volume claims created"
}

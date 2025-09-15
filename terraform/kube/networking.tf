# Tailscale Networking Configuration

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
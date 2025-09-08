
module "kube" {
  source                  = "./kube"
  project_id              = var.project_id
  zone                    = var.zone
  region                  = var.region
  cluster_name            = var.cluster_name
  node_machine_type       = var.node_machine_type
  node_disk_size          = var.node_disk_size
  use_spot_instances      = var.use_spot_instances
  storage_class           = var.storage_class
  influxdb_storage_size   = var.influxdb_storage_size
  grafana_storage_size    = var.grafana_storage_size
  ingestor_image          = var.ingestor_image
  namespace               = var.namespace
  enphase_local_token     = var.enphase_local_token
  envoy_host              = var.envoy_host
  ts_authkey              = var.ts_authkey
  influxdb_admin_password = var.influxdb_admin_password
  influxdb_admin_token    = var.influxdb_admin_token
}


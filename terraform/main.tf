
module "infra" {
  source                  = "./infra"
  project_id              = var.project_id
  repo_name               = var.repo_name
  zone                    = var.zone
  region                  = var.region
  enphase_local_token     = var.enphase_local_token
  envoy_host              = var.envoy_host
  ts_authkey              = var.ts_authkey
  influxdb_admin_password = var.influxdb_admin_password
  influxdb_admin_token    = var.influxdb_admin_token
  github_deploy_key       = var.github_deploy_key
  github_repo_ssh_url     = var.github_repo_ssh_url
}


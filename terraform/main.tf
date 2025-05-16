// Root module to orchestrate registry and infra modules

module "sourcerepo" {
  source     = "./sourcerepo"
  project_id = var.project_id
  repo_name  = var.repo_name
}

module "infra" {
  source                = "./infra"
  project_id            = var.project_id
  repo_name             = var.repo_name
  zone                  = var.zone
  region                = var.region
  service_account_email = module.sourcerepo.vm_sa_email
  depends_on            = [module.sourcerepo]
}

// Cloud Source Repository resource name
output "repo_name" {
  description = "Cloud Source Repository name created"
  value       = module.sourcerepo.repo_name
}

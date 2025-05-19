// Root module to orchestrate registry and infra modules

module "sourcerepo" {
  source     = "./sourcerepo"
  project_id = var.project_id
  project_number = var.project_number
  repo_name  = var.repo_name
  installation_id = var.installation_id
  github_pat = var.github_pat
  
}

module "infra" {
  source                = "./infra"
  project_id            = var.project_id
  repo_name             = var.repo_name
  zone                  = var.zone
  region                = var.region
  depends_on            = [module.sourcerepo]
}

// Cloud Source Repository resource name
# output "repo_name" {
#   description = "Cloud Source Repository name created"
#   value       = module.sourcerepo.repo_name
# }

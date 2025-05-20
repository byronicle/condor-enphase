terraform {
  backend "gcs" {
    bucket = "condor-enphase-tfstate"
    prefix = "terraform/state"
  }
}
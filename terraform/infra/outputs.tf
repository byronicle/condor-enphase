output "instance_ip" {
  value       = google_compute_instance.enphase.network_interface[0].access_config[0].nat_ip
  description = "External IP of the Enphase VM"
}

output "service_account_email" {
  value       = module.service_accounts.email["enphase-vm"]
  description = "Service account email used by the VM for source repo access"
}

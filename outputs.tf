output "admin_client" {
  description = "Administrative Client System"
  value       = "ssh ${var.ssh_username}@${google_compute_instance.client_instance.network_interface[0].access_config[0].nat_ip}"
}
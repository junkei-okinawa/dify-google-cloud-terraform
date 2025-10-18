resource "google_filestore_instance" "default" {
  name     = "dify-filestore"
  location = "${var.region}-b"
  tier     = "BASIC_HDD"

  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "share1"
  }

  networks {
    network = var.vpc_network_name
    modes   = ["MODE_IPV4"]
  }
  
  labels = var.labels
}
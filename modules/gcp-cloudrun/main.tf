resource "google_cloud_run_v2_service" "default" {
  name     = "mountire-cloudrun"
  location = "us-central1"
  deletion_protection = false
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
        
    }
  }
}
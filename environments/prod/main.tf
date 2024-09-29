variable "project_id" {
    type = string
    description = "The ID of the project to deploy to"
}

variable "region" {
    type = string
    description = "The region to deploy to"
}

variable "zone" {
    type = string
    description = "The zone to deploy to"
}

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 6.1.0"
    }
  }
  backend "gcs" {}
}
provider "google" {
  project = var.project_id
  region = var.region
}

module "cloud_run_service_account" {
  source = "../../modules/gcp-service-account"
  service_account_id = "mountire-cloudrun"
  display_name = "Mountire Cloud Run Service Account"
  project_id = var.project_id
  roles = [
    "roles/secretmanager.secretAccessor",
  ]
}

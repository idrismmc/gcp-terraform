variable "secret_id" {
    description = "The ID of the secret"
    type = string
    default = "resend-api"
}

variable "label" {
    description = "The label of the secret"
    type = string
    default = "gcp-terraform-cloudrun"
}
variable "service_account_id" {
    description = "The ID of the service account"
    type = string
}

variable "display_name" {
    description = "The display name of the service account"
    type = string
}

variable "project_id" {
    description = "The ID of the project"
    type = string
}

variable "roles" {
    description = "The roles to bind to the service account"
    type = list(string)
    default = []
}


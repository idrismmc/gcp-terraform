# variable "gcp_service_list" {
#     description = "The list of GCP services to enable"
#     type = list(string)
#     default = [ 
#         "cloudresourcemanager.googleapis.com", 
#         "iam.googleapis.com" 
#     ]
# }



resource "google_service_account" "service_account" {
    account_id = var.service_account_id
    display_name = var.display_name
    project = var.project_id

    # depends_on = [ google_project_service.service ]
}

resource "google_project_iam_member" "service_account_iam_policy" {
    for_each = toset(var.roles)
    project = var.project_id
    role = each.value
    member = "serviceAccount:${google_service_account.service_account.email}"
}







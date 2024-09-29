# GCP Terraform Beginner Tutorial

This is a beginner tutorial for GCP Terraform. This tutorial will help you to understand the basics of Terraform and how to use it to deploy infrastructure on GCP.

### Usage

1. Run the gcp-terraform-setup.sh script to setup the GCP project, storage bucket and service account.

   ```
   bash gcp-terraform-setup.sh --project=PROJECT_ID --env=<dev,stage,prod>
   ```

   Note: You can use the same script to setup multiple environments by changing the env parameter and your desired project id. Update the terraform_roles and services_api list in the script as per your requirement.

2. Once the initial setup is complete, you can start writing your terraform code and push to your repository. Github Actions will automatically run the terraform code and deploy the infrastructure on GCP.
3. To test locally you can set GOOGLE_CREDENTIALS environment variable to the service account key file.
   ```
   export GOOGLE_CREDENTIALS=path-to-service-account-key.json
   ```
   ```
   terraform init --backend-config="bucket=<bucket_name>"
   terraform plan
   terraform apply
   ```

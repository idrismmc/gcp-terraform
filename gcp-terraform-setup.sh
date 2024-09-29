#!/bin/bash

ERROR='\033[0;31m'
NC='\033[0m'

terraform_roles=(
    "roles/storage.admin"
    "roles/servicemanagement.quotaAdmin"
    "roles/iam.serviceAccountCreator"
    "roles/iam.serviceAccountDeleter"
    "roles/resourcemanager.projectIamAdmin"
)

services_api=(
    "cloudresourcemanager.googleapis.com"
    "iam.googleapis.com"
)

create_project() {
    local PROJECT_ID=$1
    local ENVIRONMENT=$2

    echo "Setting up project: $PROJECT_ID for environment: $ENVIRONMENT"
    echo

    echo "Checking if project $PROJECT_ID exists..."
    if gcloud projects describe $PROJECT_ID &>/dev/null; then
        echo "Project $PROJECT_ID already exists. Skipping creation."
    else
        echo "Creating project: $PROJECT_ID"
        if gcloud projects create $PROJECT_ID --set-as-default; then
            echo "Project $PROJECT_ID created successfully."
        else
            echo -e "${ERROR}Failed to create project $PROJECT_ID."
            echo "Please check the gcloud command output above for more details."
            exit 1
        fi
    fi
    echo
    echo

    echo "Setting current project..."
    if gcloud config set project $PROJECT_ID; then
        echo "Project set successfully."
    else
        echo -e "${ERROR}Failed to set project."
        exit 1
    fi
    echo "Current project: $(gcloud config get-value project)"
    echo
    echo
}

setup_project() {
    local PROJECT_ID=$1
    local ENVIRONMENT=$2
    local BUCKET_NAME=$3
    local LOCATION=$4
    local SERVICE_ACCOUNT_NAME="$PROJECT_ID-tf-sa"
    local SERVICE_ACCOUNT="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
    local SERVICE_ACCOUNT_FILE="$PROJECT_ID-$ENVIRONMENT-tf-sa.json"

    echo "Linking project to billing account..."
    if gcloud billing projects describe $PROJECT_ID | grep -q "billingEnabled: true"; then
        echo "Project is already linked to a billing account.";
    else
        echo -e "${ERROR}Project is not linked to a billing account. ${NC}Linking project to billing account...";
        if gcloud billing projects link $PROJECT_ID --billing-account=$(gcloud billing accounts list --format="json" --filter="OPEN:True" | grep name | cut -d'"' -f4); then
            echo "Project linked to billing account successfully.";
        else
            echo -e "${ERROR}Failed to link project to billing account.";
            exit 1;
        fi
    fi
    echo
    echo

    echo "Enabling APIs if not enabled already..."
    declare SERVICES_LIST=$(gcloud services list --enabled --format="json" --project=$PROJECT_ID --flatten="name" | grep -oP '[^/]+\.googleapis\.com')
    for service in "${services_api[@]}"; do
        echo "$SERVICES_LIST" | grep -q "$service" && echo "$service already enabled. Continuing..." ||
        {
            echo "$service not enabled. Enabling now...";
            if gcloud services enable $service --project=$PROJECT_ID; then
                echo "$service enabled successfully"
            else
                echo -e "${ERROR}Failed to enable $service."; 
                exit 1;
            fi
        }
    done
    echo
    echo

    echo "Creating service account for terraform deployments..."
    declare EXISTING_SERVICE_ACCOUNT=$(gcloud iam service-accounts list --filter="displayName:Terraform Service Account" --project=$PROJECT_ID --format="json" | grep email | cut -d'"' -f4)
    if [ "$EXISTING_SERVICE_ACCOUNT" = "$SERVICE_ACCOUNT" ]; then
        echo "Service account already exists.";
    else
        echo -e "${ERROR}Service account doesn't exist. ${NC}Creating a new service account...";
        if gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME --project=$PROJECT_ID --description="Service Account for terraform deployments" --display-name="Terraform Service Account ($ENVIRONMENT)"; then
            echo "Service account created successfully."
        else
            echo -e "${ERROR}Failed to create service account."
            exit 1
        fi
    fi
    echo
    echo

    echo "Granting roles to service account..."
    declare CURRENT_ROLES=$(gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members"  --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT" --format="json" | grep role | cut -d'"' -f4)
    for role in "${terraform_roles[@]}"; do
        echo "$CURRENT_ROLES" | grep -q $role && echo "$role already granted. Continuing..." ||
        { 
            echo "$role not granted. Granting access now...";
            if gcloud projects add-iam-policy-binding $PROJECT_ID --role=$role --member="serviceAccount:$SERVICE_ACCOUNT"; then
                echo "$role granted successfully.";
            else
                echo -e "${ERROR}Failed to grant role: $role.";
                exit 1;
            fi
        }
    done 

    echo "Creating new key for service account..."
    KEY_IDS=$(gcloud iam service-accounts keys list --iam-account=$SERVICE_ACCOUNT --format="json" --filter="keyType:USER_MANAGED" | grep name | cut -d'"' -f4);
    if [ -z "$KEY_IDS" ]; then
        echo "There are no existing keys for this service account. Creating new key...";
        if gcloud iam service-accounts keys create $SERVICE_ACCOUNT_FILE --iam-account=$SERVICE_ACCOUNT; then
            echo "Key created successfully.";
        else
            echo -e "${ERROR}Failed to create key for service account.";
            exit 1;
        fi
    else
        echo "Key already exists for service account. Deleting existing keys...";
        for key in $KEY_IDS; do
            if gcloud iam service-accounts keys delete $key --iam-account=$SERVICE_ACCOUNT --quiet; then
                echo "Deleted key: $key";
            else
                echo -e "${ERROR}Failed to delete key: $key.";
                exit 1;
            fi
        done

        echo "Creating new key for service account...";
        if gcloud iam service-accounts keys create $SERVICE_ACCOUNT_FILE --iam-account=$SERVICE_ACCOUNT; then
            echo "Key created successfully.";
        else
            echo -e "${ERROR}Failed to create key for service account.";
            exit 1;
        fi
    fi
    echo
    echo


    echo "Check if bucket exists already then do nothing, else create bucket...";
    if gsutil ls -b "gs://$BUCKET_NAME"; then
        echo "Bucket already exists. State file will be stored in this bucket.";
    else
        echo -e "${ERROR}Bucket doesn't exist. ${NC}Creating a new state bucket...";
        if gsutil mb -l "$LOCATION" "gs://$BUCKET_NAME"; then
            echo "Bucket created successfully.";
        else
            echo -e "${ERROR}Failed to create bucket.";
            exit 1;
        fi
        echo
        
        echo "Enabling versioning...";
        if gsutil versioning set on "gs://$BUCKET_NAME"; then
            echo "Versioning enabled successfully.";
        else
            echo -e "${ERROR}Failed to enable versioning.";
        fi
        echo

        echo "Setting uniform bucket-level access...";
        if gsutil uniformbucketlevelaccess set on "gs://$BUCKET_NAME"; then
            echo "Uniform bucket-level access set successfully.";
        else
            echo -e "${ERROR}Failed to set uniform bucket-level access.";
        fi
        echo

        echo "Setting public access prevention...";
        if gsutil pap set enforced "gs://$BUCKET_NAME"; then
            echo "Public access prevention set successfully.";
        else
            echo -e "${ERROR}Failed to set public access prevention.";
        fi
        echo "Bucket setup completed successfully.";
    fi
    echo
    echo

    echo "$PROJECT_ID setup completed successfully."
    echo "Bucket name: $BUCKET_NAME"
    echo
    echo
}

# Initialize variables with default values
PROJECT_ID=""
ENVIRONMENT=""
BUCKET_SUFFIX="tfstate"
LOCATION="US"

# Function to print usage
usage() {
    echo "Usage: $0 --project=PROJECT_ID --env=ENVIRONMENT [--bucket-suffix=BUCKET_SUFFIX] [--location=LOCATION]"
    echo "  --project        : (Required) The GCP project ID"
    echo "  --env            : (Required) The environment (dev, stage, or prod)"
    echo "  --bucket-suffix  : (Optional) Suffix for the state bucket name (default: tfstate)"
    echo "  --location       : (Optional) Location for GCS bucket (default: US)"
    echo "Example: $0 --project=my-project-id --env=dev --bucket-suffix=state --location=EU"
}

# Parse named parameters
while [ $# -gt 0 ]; do
    case "$1" in
        --project=*)
            PROJECT_ID="${1#*=}"
            ;;
        --env=*)
            ENVIRONMENT="${1#*=}"
            ;;
        --bucket-suffix=*)
            BUCKET_SUFFIX="${1#*=}"
            ;;
        --location=*)
            LOCATION="${1#*=}"
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown parameter '$1'"
            usage
            exit 1
            ;;
    esac
    shift
done

# Validate required parameters
if [ -z "$PROJECT_ID" ] || [ -z "$ENVIRONMENT" ]; then
    echo "Error: Missing required parameters"
    usage
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|stage|prod)$ ]]; then
    echo "Error: Invalid environment. Must be one of: dev, stage, prod"
    usage
    exit 1
fi

BUCKET_NAME="$PROJECT_ID-$ENVIRONMENT-$BUCKET_SUFFIX"
# Execute the main functions
create_project "$PROJECT_ID" "$ENVIRONMENT"
setup_project "$PROJECT_ID" "$ENVIRONMENT" "$BUCKET_NAME" "$LOCATION"

echo "Authenticate Github CLI..."
if ! command -v gh &>/dev/null; then
    echo "Install gh first"
    exit 1
else
    echo "gh cli is installed"
fi
if ! gh auth status &>/dev/null; then
    echo "You need to login: gh auth login"
    gh auth login
else
    echo -n "gh cli is authenticated as: " && gh auth status | grep -oP '(?<=account )\S+'
fi
echo
echo

echo "Uploading service account key and project id to Github Secrets..."
if 
    TF_SERVICE_ACCOUNT_KEY=$(cat "$PROJECT_ID-$ENVIRONMENT-tf-sa.json" | tr -d '\n')
    gh secret set "${ENVIRONMENT^^}_TF_SERVICE_ACCOUNT_KEY" --body "$TF_SERVICE_ACCOUNT_KEY"
    gh secret set "${ENVIRONMENT^^}_PROJECT_ID" --body "$PROJECT_ID"
    gh secret set "${ENVIRONMENT^^}_BUCKET_NAME" --body "$BUCKET_NAME"
then
    echo "Service account key, project id, and bucket name uploaded successfully for $ENVIRONMENT environment."
else
    echo -e "${ERROR}Failed to upload."
fi
echo
echo

echo "Script execution completed."
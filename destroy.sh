#!/usr/bin/env bash
# Destroy all infrastructure provisioned by Terraform and clean up container images.
# Comments are in English per coding guideline.

set -euo pipefail

# ---------- Configuration helpers ---------- #
TERRAFORM_TFVARS="terraform/terraform.tfvars"

# Attempt to read project ID from terraform.tfvars
if [[ -f "${TERRAFORM_TFVARS}" ]]; then
  # Extract value of gcp_project_id (strip quotes and comments)
  GCP_PROJECT_ID_FROM_TFVARS=$(grep -E '^[[:space:]]*gcp_project_id[[:space:]]*=' "${TERRAFORM_TFVARS}" \
      | awk -F'=' '{print $2}' \
      | sed -e 's/[[:space:]]*#.*//' -e 's/"//g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# Source selection order: tfvars -> env var -> user prompt
if [[ -n "${GCP_PROJECT_ID_FROM_TFVARS:-}" ]]; then
  export GCP_PROJECT_ID="${GCP_PROJECT_ID_FROM_TFVARS}"
elif [[ -n "${TF_VAR_gcp_project_id:-}" ]]; then
  export GCP_PROJECT_ID="${TF_VAR_gcp_project_id}"
else
  printf "Error: gcp_project_id not found in %s or TF_VAR_gcp_project_id env var.\n" "${TERRAFORM_TFVARS}"
  read -rp "Please enter the GCP Project ID: " GCP_PROJECT_ID_INPUT
  [[ -z "${GCP_PROJECT_ID_INPUT}" ]] && { echo "Project ID cannot be empty. Aborting."; exit 1; }
  export GCP_PROJECT_ID="${GCP_PROJECT_ID_INPUT}"
fi

# Optional variables (keep same defaults as deploy script)
export GCP_REGION="${TF_VAR_gcp_region:-us-central1}"
export SERVICE_NAME="${TF_VAR_cloud_run_service_name:-n8n}"
export IMAGE_TAG="gcr.io/${GCP_PROJECT_ID}/${SERVICE_NAME}:latest"

# ---------- Prerequisite checks ---------- #
command -v gcloud >/dev/null 2>&1 || { echo >&2 "gcloud CLI is required but not installed. Aborting."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo >&2 "terraform is required but not installed. Aborting."; exit 1; }

[[ -f "${TERRAFORM_TFVARS}" ]] || { echo >&2 "${TERRAFORM_TFVARS} file not found. Aborting."; exit 1; }

# ---------- Show configuration ---------- #
cat <<EOF
--- Destruction Configuration ---
Project ID   : ${GCP_PROJECT_ID}
Region       : ${GCP_REGION}
Image Tag    : ${IMAGE_TAG}
--------------------------------
EOF

# ---------- Confirm ---------- #
read -rp "Are you absolutely sure you want to destroy ALL resources in project ${GCP_PROJECT_ID}? (y/N) " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted by user."; exit 0; }

# Use the correct project for all subsequent gcloud commands
gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

# ---------- Step 1: Terraform destroy ---------- #
echo -e "\n---> Running 'terraform destroy'..."
pushd terraform >/dev/null
terraform init -reconfigure
terraform destroy -auto-approve
popd >/dev/null

# ---------- Step 2: Delete container image (Container Registry) ---------- #
# NOTE: If you switched to Artifact Registry, adjust the delete command accordingly.
# echo -e "\n---> Deleting container image ${IMAGE_TAG} (ignore errors if it does not exist)..."
# gcloud container images delete \
#   --quiet --force-delete-tags "${IMAGE_TAG}" || true

# ---------- Completion ---------- #
echo -e "\n---> Infrastructure and images have been destroyed."
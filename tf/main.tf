# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

data "google_project" "project" {}

# 1. Enable Required APIs
resource "google_project_service" "enable_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "agentregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "storage-api.googleapis.com",
    "iam.googleapis.com",
    "cloudbilling.googleapis.com",
    "container.googleapis.com",
    "apphub.googleapis.com",
    "logging.googleapis.com",
    "telemetry.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "run.googleapis.com",
    "designcenter.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "modelarmor.googleapis.com",
    "cloudasset.googleapis.com",
    "servicehealth.googleapis.com",
    "config.googleapis.com",
    "apptopology.googleapis.com",
    "cloudapiregistry.googleapis.com",
    "iamconnectors.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com",
    "observability.googleapis.com",
    "saasservicemgmt.googleapis.com",
    "securitycenter.googleapis.com",
    "texttospeech.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

resource "time_sleep" "wait_apis" {
  depends_on      = [google_project_service.enable_apis]
  create_duration = "30s"
}

# 2. Artifact Registry for Web Portal
resource "google_artifact_registry_repository" "novasmart_repo" {
  project       = var.gcp_project_id
  location      = var.gcp_region
  repository_id = "novasmart-repo"
  description   = "Docker repository for NovaSmart Pricing Portal App"
  format        = "DOCKER"
  depends_on    = [time_sleep.wait_apis]
}

# 3. GCS Bucket to Stage Seeding Assets
resource "google_storage_bucket" "seed_bucket" {
  name          = "novasmart-seed-bucket-${var.gcp_project_id}"
  project       = var.gcp_project_id
  location      = var.gcp_region
  force_destroy = true
  depends_on    = [time_sleep.wait_apis]
}

resource "google_storage_bucket_object" "seed_sql" {
  name   = "seed-data.sql"
  bucket = google_storage_bucket.seed_bucket.name
  source = "${path.module}/db/seed-data.sql"
}

# 4. Package and Stage Price Match Agent Source Code
data "archive_file" "agent_zip" {
  type        = "zip"
  source_dir  = "${path.module}/agent"
  output_path = "${path.module}/db/agent.zip"
}

resource "google_storage_bucket_object" "agent_code" {
  name   = "agent.zip"
  bucket = google_storage_bucket.seed_bucket.name
  source = data.archive_file.agent_zip.output_path
}

resource "google_storage_bucket_object" "deploy_agent_script" {
  name   = "deploy_agent_local.py"
  bucket = google_storage_bucket.seed_bucket.name
  source = "${path.module}/deploy_agent_local.py"
}

# 5. Package and Stage Web Portal Source Code
data "archive_file" "ui_zip" {
  type        = "zip"
  source_dir  = "${path.module}/ui"
  output_path = "${path.module}/db/ui.zip"
}

resource "google_storage_bucket_object" "ui_code" {
  name   = "ui.zip"
  bucket = google_storage_bucket.seed_bucket.name
  source = data.archive_file.ui_zip.output_path
}

# 5b. Package and Stage Markdown Strategy Agent Source Code
data "archive_file" "strategy_agent_zip" {
  type        = "zip"
  source_dir  = "${path.module}/strategy_agent"
  output_path = "${path.module}/db/strategy_agent.zip"
}

resource "google_storage_bucket_object" "strategy_agent_code" {
  name   = "strategy_agent.zip"
  bucket = google_storage_bucket.seed_bucket.name
  source = data.archive_file.strategy_agent_zip.output_path
}

# 6. BigQuery Dataset creation
resource "google_bigquery_dataset" "pricing_dataset" {
  dataset_id                  = "novasmart_pricing"
  friendly_name               = "novasmart_pricing"
  description                 = "NovaSmart Pricing Catalog Dataset"
  location                    = "US"
  project                     = var.gcp_project_id
  delete_contents_on_destroy  = true
  depends_on                  = [time_sleep.wait_apis]
}



# 7. Asynchronous GCE Build Helper to trigger Cloud Build
resource "google_compute_instance" "build_helper_vm" {
  name         = "novasmart-build-helper"
  project      = var.gcp_project_id
  machine_type = "e2-medium"
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    startup-script = <<-SCRIPT
      #!/bin/bash
      # Allow script to fail safely to write FAILED state to GCS
      set -x

      # Install unzip, pip, venv
      apt-get update && apt-get install -y unzip python3-pip python3-venv

      # Seeding BigQuery catalog
      gsutil cp gs://${google_storage_bucket.seed_bucket.name}/${google_storage_bucket_object.seed_sql.name} /tmp/seed-data.sql
      bq query --project_id=${var.gcp_project_id} --use_legacy_sql=false < /tmp/seed-data.sql

      # 1. Cloud Run Portal Build
      gsutil cp gs://${google_storage_bucket.seed_bucket.name}/${google_storage_bucket_object.ui_code.name} /tmp/ui.zip
      mkdir -p /tmp/ui
      unzip /tmp/ui.zip -d /tmp/ui

      cd /tmp/ui
      if ! gcloud builds submit --tag ${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/novasmart-repo/novasmart-store-portal:latest --project=${var.gcp_project_id} . > /tmp/build.log 2>&1; then
        echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
        gsutil cp /tmp/build.log gs://${google_storage_bucket.seed_bucket.name}/build.log
        exit 1
      fi

      # 1b. Price Match Agent Container Build (Commented out since we are using GCS Source Package)
      # gsutil cp gs://${google_storage_bucket.seed_bucket.name}/${google_storage_bucket_object.agent_code.name} /tmp/agent_img.zip
      # mkdir -p /tmp/agent_img
      # unzip /tmp/agent_img.zip -d /tmp/agent_img
      # cd /tmp/agent_img
      # if ! gcloud builds submit --tag ${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/novasmart-repo/price-match-agent:latest --project=${var.gcp_project_id} . > /tmp/agent_build.log 2>&1; then
      #   echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
      #   gsutil cp /tmp/agent_build.log gs://${google_storage_bucket.seed_bucket.name}/agent_build.log
      #   exit 1
      # fi



      # 2. Agent Pickle Compilation
      gsutil cp gs://${google_storage_bucket.seed_bucket.name}/${google_storage_bucket_object.agent_code.name} /tmp/agent.zip
      mkdir -p /tmp/agent/agent
      unzip /tmp/agent.zip -d /tmp/agent/agent

      python3 -m venv /opt/venv
      source /opt/venv/bin/activate
      if ! pip install --no-cache-dir --prefer-binary cloudpickle -r /tmp/agent/agent/requirements.txt > /tmp/pip.log 2>&1; then
        echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
        gsutil cp /tmp/pip.log gs://${google_storage_bucket.seed_bucket.name}/pip.log
        exit 1
      fi

      cd /tmp/agent
      if ! python3 -c "
      import sys
      sys.path.append('.')
      from agent import price_match_agent
      import cloudpickle

      cloudpickle.register_pickle_by_value(price_match_agent)

      with open('/tmp/agent/pickle_object.bin', 'wb') as f:
          cloudpickle.dump(price_match_agent.agent_engine, f)
      " > /tmp/pickle.log 2>&1; then
        echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
        gsutil cp /tmp/pickle.log gs://${google_storage_bucket.seed_bucket.name}/pickle.log
        exit 1
      fi

      # Upload pickle object and requirements file to GCS
      gsutil cp /tmp/agent/pickle_object.bin gs://${google_storage_bucket.seed_bucket.name}/pickle_object.bin
      gsutil cp /tmp/agent/agent/requirements.txt gs://${google_storage_bucket.seed_bucket.name}/requirements.txt

      # 3. Deploy Markdown Strategy Agent (Commented out for now)
      # gsutil cp gs://${google_storage_bucket.seed_bucket.name}/strategy_agent.zip /tmp/strategy_agent.zip
      # mkdir -p /tmp/strategy_agent
      # unzip /tmp/strategy_agent.zip -d /tmp/strategy_agent
      # cd /tmp/strategy_agent
      # if ! pip install --no-cache-dir --prefer-binary -r requirements.txt > /tmp/pip_strategy.log 2>&1; then
      #   echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
      #   gsutil cp /tmp/pip_strategy.log gs://${google_storage_bucket.seed_bucket.name}/pip_strategy.log
      #   exit 1
      # fi
      # export GOOGLE_CLOUD_PROJECT="${var.gcp_project_id}"
      # export GOOGLE_CLOUD_REGION="${var.gcp_region}"
      # if ! python3 deploy_strategy_agent.py > /tmp/deploy_strategy.log 2>&1; then
      #   echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
      #   gsutil cp /tmp/deploy_strategy.log gs://${google_storage_bucket.seed_bucket.name}/deploy_strategy.log
      #   exit 1
      # fi
      # gsutil cp /tmp/strategy_agent_id.txt gs://${google_storage_bucket.seed_bucket.name}/strategy_agent_id.txt

      # 4. Deploy Price Match Agent (A1) (Commented out to let students deploy via ADC)
      cd /tmp/agent
      export GOOGLE_CLOUD_PROJECT="${var.gcp_project_id}"
      export GOOGLE_CLOUD_REGION="${var.gcp_region}"
      gsutil cp gs://${google_storage_bucket.seed_bucket.name}/deploy_agent_local.py /tmp/agent/deploy_agent_local.py
      if ! python3 deploy_agent_local.py > /tmp/deploy_agent.log 2>&1; then
        echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
        gsutil cp /tmp/deploy_agent.log gs://${google_storage_bucket.seed_bucket.name}/deploy_agent.log
        exit 1
      fi
      # Extract deployed Price Match Agent ID
      PMA_ID=$(tail -n 30 /tmp/deploy_agent.log | grep -oP "Agent Engine ID: \K\d+")

      # 5. Deploy Cloud Run storefront-portal-proxy (Commented out to let students deploy via ADC)
      if ! gcloud run deploy novasmart-store-portal \
        --image=${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/novasmart-repo/novasmart-store-portal:latest \
        --region=${var.gcp_region} \
        --project=${var.gcp_project_id} \
        --update-env-vars=AGENT_ENGINE_ID=$PMA_ID,GCP_PROJECT_ID=${var.gcp_project_id} \
        --allow-unauthenticated > /tmp/deploy_ui.log 2>&1; then
        echo "FAILED" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
        gsutil cp /tmp/deploy_ui.log gs://${google_storage_bucket.seed_bucket.name}/deploy_ui.log
        exit 1
      fi

      # Write final success status
      echo "SUCCESS" | gsutil cp - gs://${google_storage_bucket.seed_bucket.name}/build_status.txt
    SCRIPT
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [
    google_storage_bucket_object.ui_code,
    google_artifact_registry_repository.novasmart_repo
  ]
}

# 8. Synchronous Verification of Cloud Build status via GCS polling
data "google_client_config" "default" {}

resource "terraform_data" "verify_build" {
  triggers_replace = [
    google_compute_instance.build_helper_vm.id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for build helper VM to complete Cloud Build..."
      TOKEN="${data.google_client_config.default.access_token}"
      BUCKET="${google_storage_bucket.seed_bucket.name}"
      URL="https://storage.googleapis.com/storage/v1/b/$BUCKET/o/build_status.txt?alt=media"
      
      i=1
      while [ $i -le 60 ]; do
        STATUS=$(curl -s -f -H "Authorization: Bearer $TOKEN" "$URL" || true)
        if [ "$STATUS" = "SUCCESS" ]; then
          echo "✅ Storefront Portal container image built and pushed successfully!"
          exit 0
        elif [ "$STATUS" = "FAILED" ]; then
          echo "❌ Build helper failed inside the VM!"
          for log_file in build.log pip.log pickle.log deploy_strategy.log deploy_agent.log deploy_ui.log; do
            LOG_URL="https://storage.googleapis.com/storage/v1/b/$BUCKET/o/$log_file?alt=media"
            if curl -s -f -H "Authorization: Bearer $TOKEN" "$LOG_URL" > /tmp/temp_failed.log; then
              echo "--- ERROR LOG DETECTED: $log_file ---"
              cat /tmp/temp_failed.log
              echo "----------------------------------------"
              exit 1
            fi
          done
          echo "No log files found in GCS bucket."
          exit 1
        fi
        echo "Build in progress... waiting 15 seconds (attempt $i/60)..."
        sleep 15
        i=$((i+1))
      done
      echo "❌ Timeout waiting for helper VM to complete build!"
      exit 1
    EOT
  }

  depends_on = [google_compute_instance.build_helper_vm]
}

# 9. Service Account IAM Permissions for App Design Center Pipelines and VM Build Helper
locals {
  build_sa   = "${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  compute_sa = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "build_permissions" {
  project  = var.gcp_project_id
  for_each = toset([
    "roles/aiplatform.admin",
    "roles/run.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountUser",
    "roles/artifactregistry.writer",
    "roles/resourcemanager.projectIamAdmin",
  ])
  role   = each.key
  member = "serviceAccount:${local.build_sa}"
  depends_on = [google_project_service.enable_apis]
}

resource "google_project_iam_member" "compute_permissions" {
  project  = var.gcp_project_id
  for_each = toset([
    "roles/aiplatform.admin",
    "roles/run.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountUser",
    "roles/artifactregistry.writer",
    "roles/resourcemanager.projectIamAdmin",
    "roles/bigquery.admin",
  ])
  role   = each.key
  member = "serviceAccount:${local.compute_sa}"
  depends_on = [google_project_service.enable_apis]
}

# 10. Service Accounts for Application Personas (Associate and Manager)
resource "google_service_account" "storeagent" {
  account_id   = "novasmart-storeagent"
  display_name = "NovaSmart Store Agent (Associate Persona)"
  project      = var.gcp_project_id
}

resource "google_service_account" "manager" {
  account_id   = "novasmart-manager"
  display_name = "NovaSmart Manager Persona"
  project      = var.gcp_project_id
}

# Grant Vertex AI User role to both personas to invoke Reasoning Engines
resource "google_project_iam_member" "persona_vertex_user" {
  for_each = toset([
    "serviceAccount:${google_service_account.storeagent.email}",
    "serviceAccount:${google_service_account.manager.email}"
  ])
  project = var.gcp_project_id
  role    = "roles/aiplatform.user"
  member  = each.key
}

# Allow Compute Engine default service account (which runs Cloud Run storefront portal)
# to impersonate (create tokens for) both persona service accounts.
resource "google_service_account_iam_member" "impersonate_storeagent" {
  service_account_id = google_service_account.storeagent.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_service_account_iam_member" "impersonate_manager" {
  service_account_id = google_service_account.manager.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

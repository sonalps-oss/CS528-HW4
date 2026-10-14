#!/bin/bash
set -euo pipefail
: "${PROJECT_ID:?Set PROJECT_ID}" "${BUCKET:?Set BUCKET}"
ZONE="${ZONE:-us-central1-a}"
REGION="${REGION:-${ZONE%-*}}"
SERVER_TYPE="${SERVER_TYPE:-e2-micro}"
CLIENT_TYPE="${CLIENT_TYPE:-e2-small}"
gcloud config set project "$PROJECT_ID"
gcloud services enable compute.googleapis.com storage.googleapis.com logging.googleapis.com monitoring.googleapis.com pubsub.googleapis.com iam.googleapis.com
for sa in hw4-server hw4-reporter; do
  gcloud iam service-accounts describe "$sa@$PROJECT_ID.iam.gserviceaccount.com" >/dev/null 2>&1 || gcloud iam service-accounts create "$sa" --display-name="$sa"
done
SERVER_SA="hw4-server@$PROJECT_ID.iam.gserviceaccount.com"
REPORTER_SA="hw4-reporter@$PROJECT_ID.iam.gserviceaccount.com"
for sa in "$SERVER_SA" "$REPORTER_SA"; do
  gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$sa" --role="roles/storage.objectViewer" >/dev/null
done
for role in roles/logging.logWriter roles/monitoring.metricWriter; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$SERVER_SA" --role="$role" --quiet >/dev/null
done
gcloud pubsub topics describe hw4-forbidden >/dev/null 2>&1 || gcloud pubsub topics create hw4-forbidden
gcloud pubsub topics add-iam-policy-binding hw4-forbidden --member="serviceAccount:$SERVER_SA" --role=roles/pubsub.publisher >/dev/null
gcloud pubsub subscriptions describe hw4-forbidden-sub >/dev/null 2>&1 || gcloud pubsub subscriptions create hw4-forbidden-sub --topic=hw4-forbidden
gcloud pubsub subscriptions add-iam-policy-binding hw4-forbidden-sub --member="serviceAccount:$REPORTER_SA" --role=roles/pubsub.subscriber >/dev/null
# Publish source files to bucket. GET forbids the hw4-code/ prefix.
gcloud storage cp server.py reporter.py "gs://$BUCKET/hw4-code/"
gcloud compute addresses describe hw4-server-ip --region="$REGION" >/dev/null 2>&1 || gcloud compute addresses create hw4-server-ip --region="$REGION"
IP="$(gcloud compute addresses describe hw4-server-ip --region="$REGION" --format='value(address)')"
gcloud compute firewall-rules describe hw4-allow-http >/dev/null 2>&1 || gcloud compute firewall-rules create hw4-allow-http --network=default --allow=tcp:8080 --source-ranges=0.0.0.0/0 --target-tags=hw4-http
metadata="hw4-bucket=$BUCKET,hw4-project=$PROJECT_ID"
if ! gcloud compute instances describe hw4-server --zone="$ZONE" >/dev/null 2>&1; then
  gcloud compute instances create hw4-server --zone="$ZONE" --machine-type="$SERVER_TYPE" --image-family=debian-12 --image-project=debian-cloud --boot-disk-size=10GB --address="$IP" --network=default --tags=hw4-http --service-account="$SERVER_SA" --scopes=cloud-platform --metadata="$metadata,hw4-role=server" --metadata-from-file=startup-script=startup.sh
fi
if ! gcloud compute instances describe hw4-reporter --zone="$ZONE" >/dev/null 2>&1; then
  gcloud compute instances create hw4-reporter --zone="$ZONE" --machine-type=e2-micro --image-family=debian-12 --image-project=debian-cloud --boot-disk-size=10GB --network=default --service-account="$REPORTER_SA" --scopes=cloud-platform --metadata="$metadata,hw4-role=reporter" --metadata-from-file=startup-script=startup.sh
fi
# Client has no Cloud API permissions and uses the default compute service account with restricted scope.
if ! gcloud compute instances describe hw4-client --zone="$ZONE" >/dev/null 2>&1; then
  gcloud compute instances create hw4-client --zone="$ZONE" --machine-type="$CLIENT_TYPE" --image-family=debian-12 --image-project=debian-cloud --boot-disk-size=10GB --network=default --no-service-account --no-scopes
fi
printf '\nServer URL: http://%s:8080/\nZone: %s\n' "$IP" "$ZONE"

#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/hw4-startup.log) 2>&1
md() { curl -fsS -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
ROLE="$(md hw4-role)"
BUCKET="$(md hw4-bucket)"
PROJECT_ID="$(md hw4-project)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv curl
mkdir -p /opt/hw4
python3 -m venv /opt/hw4/.venv
/opt/hw4/.venv/bin/pip install --disable-pip-version-check google-cloud-storage google-cloud-logging google-cloud-pubsub
# Download code from an authenticated bucket using the VM's service account.
BUCKET="$BUCKET" ROLE="$ROLE" /opt/hw4/.venv/bin/python - <<'PY'
import os
from google.cloud import storage
client=storage.Client()
source='server.py' if os.environ['ROLE']=='server' else 'reporter.py'
client.bucket(os.environ['BUCKET']).blob('hw4-code/'+source).download_to_filename('/opt/hw4/'+source)
PY
useradd --system --home /opt/hw4 --shell /usr/sbin/nologin hw4app 2>/dev/null || true
chown -R hw4app:hw4app /opt/hw4
if [ "$ROLE" = 'server' ]; then
cat >/etc/systemd/system/hw4.service <<EOF
[Unit]
Description=CS528 HW4 HTTP server
After=network-online.target
Wants=network-online.target
[Service]
User=hw4app
WorkingDirectory=/opt/hw4
Environment=PROJECT_ID=$PROJECT_ID
Environment=BUCKET=$BUCKET
Environment=TOPIC=hw4-forbidden
Environment=PORT=8080
ExecStart=/opt/hw4/.venv/bin/python /opt/hw4/server.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
else
cat >/etc/systemd/system/hw4.service <<EOF
[Unit]
Description=CS528 HW4 banned-country reporter
After=network-online.target
Wants=network-online.target
[Service]
User=hw4app
WorkingDirectory=/opt/hw4
Environment=PROJECT_ID=$PROJECT_ID
Environment=SUBSCRIPTION=hw4-forbidden-sub
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/hw4/.venv/bin/python /opt/hw4/reporter.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
fi
systemctl daemon-reload
systemctl enable --now hw4
# Install the Ops Agent on the server for memory and network metrics.
if [ "$ROLE" = 'server' ]; then
  curl -fsSLo /tmp/install-ops-agent.sh https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
  bash /tmp/install-ops-agent.sh --also-install
fi

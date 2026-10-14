# CS528 Homework 4 starter

See the ChatGPT step-by-step walkthrough for setup, testing, evidence and report instructions.

```bash
export PROJECT_ID='your-project'
export BUCKET='your-existing-hw2-bucket'
export ZONE='us-central1-a'
gcloud auth login
chmod +x deploy.sh
./deploy.sh
```

The script creates the `hw4-server`, `hw4-reporter`, and `hw4-client` VMs. It starts the first two services via metadata startup scripts and systemd, reserves a regional static IP for the server, creates a Pub/Sub topic/subscription, and installs the Cloud Ops Agent on the server.

**Demo-only country simulation:** send the `X-Country-Code: IR` HTTP header to simulate a blocked-country request. This is not real IP geolocation and is not a trustworthy production access control.

**Security:** Firewall allows HTTP 8080 from any IP for the browser/curl demonstration. Tighten `--source-ranges` to known addresses if possible. The server's Pub/Sub Publisher permission is scoped to the specific topic. The VM runtime identity uses managed service-account tokens, with no embedded key files.

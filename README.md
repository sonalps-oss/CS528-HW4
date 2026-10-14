
# CS528 Homework 4 — HTTP Web Server on Google Cloud Compute Engine

## Project Overview

This project implements a cloud-based HTTP web server using **Google Cloud Compute Engine virtual machines**, extending the functionality developed in Homework 3.

In HW3, the services were deployed using serverless infrastructure. In HW4, the same functionality is implemented using persistent virtual machines, dedicated service accounts, Google Cloud Storage, Cloud Logging, Cloud Pub/Sub, and Cloud Monitoring.

The project demonstrates:

- HTTP GET and POST file retrieval from Google Cloud Storage
- HTTP 200 OK responses for existing files
- HTTP 404 Not Found responses with WARNING logs
- HTTP 501 Not Implemented responses with ERROR logs
- Simulated forbidden-country detection and CRITICAL logging
- Pub/Sub communication between independent VM services
- Automatic startup using VM metadata scripts and systemd
- Automated VM deployment
- Load testing with 1–4 concurrent clients
- CPU, memory, and network bandwidth monitoring
- Cloud infrastructure cost analysis

---

## 1. Google Cloud Configuration

| Resource | Configuration |
|---|---|
| Cloud Provider | Google Cloud Platform |
| Project ID | `directed-fabric-508221-d2` |
| Region | `us-central1` |
| Zone | `us-central1-a` |
| Storage Bucket | `sonal-graph-2026-sps` |
| File Directory | `graph_data/` |
| Web Server Static IP | `34.60.83.171` |
| Web Server Port | `8080` |
| Pub/Sub Topic | `hw4-forbidden` |
| Pub/Sub Subscription | `hw4-forbidden-sub` |
| Cloud Logging Log Name | `hw4-http` |

The external IP shown above was used during the experiment. It may no longer be reachable after the resources are deleted.

---

## 2. System Architecture

The application uses three Compute Engine virtual machines.

```text
                  +----------------------+
                  |      Client VM       |
                  |      hw4-client      |
                  |      Debian 13       |
                  |       e2-small       |
                  +----------+-----------+
                             |
                             | HTTP GET / POST
                             | Port 8080
                             v
                  +----------------------+
                  |     Web Server VM    |
                  |      hw4-server      |
                  |       e2-micro       |
                  |    Python HTTP API   |
                  |     34.60.83.171     |
                  +----------+-----------+
                             |
              +--------------+---------------+
              |                              |
              v                              v
   +---------------------+       +----------------------+
   | Google Cloud Storage|       | Google Cloud Logging |
   |                     |       |                      |
   | sonal-graph-2026-sps|       | WARNING              |
   | graph_data/*.html   |       | ERROR                |
   +---------------------+       | CRITICAL             |
                                 +----------------------+

             Forbidden-country requests
                             |
                             v
                  +----------------------+
                  |   Google Pub/Sub     |
                  |    hw4-forbidden     |
                  +----------+-----------+
                             |
                             v
                  +----------------------+
                  |     Reporter VM      |
                  |     hw4-reporter     |
                  |       e2-micro       |
                  |   Pub/Sub Subscriber |
                  +----------+-----------+
                             |
                             v
                     Standard Output
```

### VM Configuration

| VM | Machine Type | Operating System | Purpose |
|---|---|---|---|
| `hw4-server` | e2-micro | Debian 12 | HTTP file server |
| `hw4-client` | e2-small | Debian 13 | HTTP client and stress testing |
| `hw4-reporter` | e2-micro | Debian 12 | Forbidden-country reporting |

The client VM uses Debian 13 because the professor-provided Linux executable requires GLIBC 2.38 or newer.

---

## 3. Project Structure

```text
CS528-HW4/
├── server.py
├── reporter.py
├── startup.sh
├── deploy.sh
├── README.md
└── stress.sh                  # Add from client VM for reproducibility
```

### File Descriptions

**server.py**

Implements the Python HTTP server using `ThreadingHTTPServer`. The server retrieves Cloud Storage objects, handles HTTP methods, writes structured error logs, and publishes forbidden-country events.

**reporter.py**

Runs a Pub/Sub subscriber on a separate VM and prints received forbidden-country events to standard output.

**startup.sh**

Installs Python dependencies and configures the application as a systemd service during VM startup.

**deploy.sh**

Automates IAM configuration, Pub/Sub resource creation, static IP allocation, firewall configuration, and VM deployment.

**stress.sh**

Repeatedly executes the professor-provided HTTP client with a configurable number of concurrent processes. This script was created on the client VM during testing and should be copied into the repository.

---

## 4. Technologies Used

| Category | Technology |
|---|---|
| Programming | Python 3, Bash |
| Compute | Google Compute Engine |
| Storage | Google Cloud Storage |
| Logging | Google Cloud Logging |
| Monitoring | Google Cloud Monitoring, Ops Agent |
| Messaging | Google Cloud Pub/Sub |
| Security | Google Cloud IAM, Service Accounts |
| HTTP Server | Python ThreadingHTTPServer |
| Process Management | systemd |
| Testing | curl, professor-provided HTTP client |
| Deployment | Google Cloud CLI, startup scripts |

---

## 5. Cloud Storage Configuration

The existing HW2/HW3 bucket is reused for HW4.

**Bucket:** `sonal-graph-2026-sps`

**Directory:** `graph_data/`

Example files:

```text
gs://sonal-graph-2026-sps/graph_data/0.html
gs://sonal-graph-2026-sps/graph_data/1.html
gs://sonal-graph-2026-sps/graph_data/10.html
gs://sonal-graph-2026-sps/graph_data/100.html
```

Verify the existing files:

```bash
gcloud storage ls \
  gs://sonal-graph-2026-sps/graph_data/
```

The Python application uses the Google Cloud Storage client library to retrieve files.

---

## 6. IAM and Service Accounts

Dedicated service accounts are used to restrict application permissions.

### Web Server Service Account

```text
hw4-server@directed-fabric-508221-d2.iam.gserviceaccount.com
```

Permissions:

- Storage Object Viewer on the existing bucket
- Logging Writer
- Monitoring Metric Writer
- Pub/Sub Publisher on the HW4 topic

### Reporter Service Account

```text
hw4-reporter@directed-fabric-508221-d2.iam.gserviceaccount.com
```

Permissions:

- Storage Object Viewer for downloading application code
- Pub/Sub Subscriber on the HW4 subscription

The deployment uses VM-attached service accounts rather than embedding service-account JSON credentials in application code.

---

## 7. Deployment Instructions

### Prerequisites

- Google Cloud account with billing enabled
- Google Cloud SDK
- Permissions to manage Compute Engine, IAM, Storage, and Pub/Sub
- Existing Storage bucket containing the HTML dataset

### Step 1: Configure Project

```bash
export PROJECT_ID="directed-fabric-508221-d2"
export BUCKET="sonal-graph-2026-sps"
export REGION="us-central1"
export ZONE="us-central1-a"

gcloud config set project "$PROJECT_ID"
```

### Step 2: Enable Required APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  storage.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  iam.googleapis.com
```

### Step 3: Update the Client Image

The original `deploy.sh` specifies Debian 12 for the client VM.

Before a fresh deployment, update only the `hw4-client` creation command to use:

```bash
--image-family=debian-13
```

The remaining VM images can stay on Debian 12.

This change is required for compatibility with the professor-provided Linux HTTP client.

### Step 4: Deploy VMs

From the project directory:

```bash
chmod +x deploy.sh
./deploy.sh
```

The deployment script:

1. Enables required APIs.
2. Creates or reuses the service accounts.
3. Configures IAM permissions.
4. Creates the Pub/Sub topic and subscription.
5. Uploads application files under `hw4-code/`.
6. Reserves a static external IP address.
7. Configures the HTTP firewall rule for port 8080.
8. Creates the three virtual machines.
9. Configures startup scripts for the server and reporter.

### Step 5: Verify Deployment

```bash
gcloud compute instances list
```

### Step 6: Verify Automatic Startup

```bash
gcloud compute ssh hw4-server \
  --zone=us-central1-a \
  --command="sudo systemctl status hw4 --no-pager"
```

Expected service state:

```text
Active: active (running)
```

Reporter service:

```bash
gcloud compute ssh hw4-reporter \
  --zone=us-central1-a \
  --command="sudo systemctl status hw4 --no-pager"
```

---

## 8. HTTP Functionality and Testing

### HTTP 200 OK — GET

```bash
curl -i \
  http://34.60.83.171:8080/graph_data/0.html
```

Expected response:

```text
HTTP/1.1 200 OK
```

The response body contains the HTML file.

### HTTP 200 OK — POST

```bash
curl -i -X POST \
  http://34.60.83.171:8080/ \
  -H "Content-Type: application/json" \
  -d '{"file":"graph_data/0.html"}'
```

Expected:

```text
HTTP/1.1 200 OK
```

### HTTP 404 Not Found

```bash
curl -i \
  http://34.60.83.171:8080/graph_data/missing.html
```

Expected:

```text
HTTP/1.1 404 Not Found
```

The server records the error with severity `WARNING`.

### HTTP 501 Not Implemented

```bash
curl -i -X PUT \
  http://34.60.83.171:8080/graph_data/0.html
```

Expected:

```text
HTTP/1.1 501 Not Implemented
```

The server records the error with severity `ERROR`.

Unsupported methods handled by the application include:

- PUT
- DELETE
- HEAD
- CONNECT
- OPTIONS
- TRACE
- PATCH

### Browser Demonstrations

The assignment additionally requires browser-based evidence for HTTP 200, 404, and 501 responses.

For HTTP 501, Developer Tools can be used to issue a PUT request:

```javascript
fetch("/graph_data/0.html", { method: "PUT" })
  .then(async response => {
    console.log("HTTP status:", response.status);
    console.log(await response.text());
  });
```

The browser's Network panel can be used to inspect the resulting HTTP status.

Screenshots of the demonstrations are documented separately in the assignment report.

---

## 9. Structured Cloud Logging

Application errors are logged using Google Cloud Logging.

**Log name:** `hw4-http`

| Scenario | HTTP Response | Severity |
|---|---|---|
| Existing file | 200 OK | No error required |
| Missing file | 404 Not Found | WARNING |
| Unsupported method | 501 Not Implemented | ERROR |
| Simulated forbidden-country request | 400 Permission Denied | CRITICAL |

### WARNING Log Query

```text
logName="projects/directed-fabric-508221-d2/logs/hw4-http"
severity=WARNING
```

### ERROR Log Query

```text
logName="projects/directed-fabric-508221-d2/logs/hw4-http"
severity=ERROR
```

### CRITICAL Log Query

```text
logName="projects/directed-fabric-508221-d2/logs/hw4-http"
severity=CRITICAL
```

The logs contain structured fields describing the request method, URL path, client IP, and error reason.

---

## 10. Forbidden-Country Reporting

The assignment defines nine countries for restricted-access testing.

| Country | Code |
|---|---|
| North Korea | KP |
| Iran | IR |
| Cuba | CU |
| Myanmar | MM |
| Iraq | IQ |
| Libya | LY |
| Sudan | SD |
| Zimbabwe | ZW |
| Syria | SY |

The server checks a simulated `X-Country-Code` request header.

### Test Request

```bash
curl -i \
  -H "X-Country-Code: IR" \
  http://34.60.83.171:8080/graph_data/0.html
```

For a simulated restricted-country request, the application:

1. Rejects access.
2. Writes a structured CRITICAL event.
3. Publishes the event to the `hw4-forbidden` Pub/Sub topic.
4. Delivers the message to the reporter VM through `hw4-forbidden-sub`.
5. Prints an error message to the reporting service's stdout.

### Inspect Reporter Output

```bash
gcloud compute ssh hw4-reporter \
  --zone=us-central1-a \
  --command="sudo journalctl -u hw4 -n 50 --no-pager"
```

**Limitation:** The header-based country check is a simulation, not real IP geolocation. The header is controlled by the HTTP client and should not be used as a trusted security control in production.

---

## 11. HTTP Client Testing

The official professor-provided Linux HTTP client was used from the separate `hw4-client` VM.

### Client Configuration

The client VM runs Debian 13 to satisfy the executable's GLIBC requirements.

The HTTP client was copied from Cloud Shell using:

```bash
gcloud compute scp ~/http-client \
  hw4-client:~/http-client \
  --zone=us-central1-a
```

### Test Command

```bash
time ./http-client \
  -d 34.60.83.171 \
  -p 8080 \
  -b none \
  -w graph_data \
  -n 100 \
  -i 99 \
  -t 15
```

### Results

| Measurement | Result |
|---|---|
| Requested files | 100 |
| HTTP 200 responses | 100 |
| Observed success rate | 100% |
| Execution time | 7.660 seconds |

The HTTP responses were verified in the server's systemd journal.

```text
100 200
```

This demonstrates successful retrieval of 100 HTML files through the VM-hosted Python web server.

---

## 12. Stress Testing

The Python server was stress tested using the professor-provided HTTP client with increasing concurrency.

The test used the `e2-micro` server VM and a separate `e2-small` client VM.

### Test Configuration

| Parameter | Value |
|---|---|
| Server VM | hw4-server |
| Client VM | hw4-client |
| Server type | e2-micro |
| Client type | e2-small |
| Port | 8080 |
| Requests per client invocation | 100 |
| Duration per round | Approximately 3 minutes |
| Maximum concurrent clients | 4 |

Each round was performed independently.

### Stress-Test Execution

The helper script repeatedly executes the professor-provided HTTP client for approximately 180 seconds.

```bash
./stress.sh 1
./stress.sh 2
./stress.sh 3
./stress.sh 4
```

The commands above were run sequentially, never at the same time.

### Test Intervals

| Clients | Start (UTC) | End (UTC) | Duration |
|---|---|---|---|
| 1 | Oct 13, 23:40:35 | Oct 13, 23:43:38 | 3m 03s |
| 2 | Oct 14, 01:14:26 | Oct 14, 01:17:28 | 3m 02s |
| 3 | Oct 14, 01:21:59 | Oct 14, 01:25:06 | 3m 07s |
| 4 | Oct 14, 01:30:20 | Oct 14, 01:33:27 | 3m 07s |

### Performance Measurements

CPU, memory, and outgoing bandwidth were captured using Google Cloud Monitoring.

The values below are approximate readings from the monitoring screenshots.

| Concurrent Clients | Displayed Peak CPU | Displayed Peak Memory | Peak Outgoing Bandwidth |
|---|---|---|---|
| 1 | ~84% | ~72.6% | ~2.15 MiB/s |
| 2 | ~124% | ~73.2% | ~3.23 MiB/s |
| 3 | ~143% | ~66.5% | ~4.70 MiB/s |
| 4 | ~133% | ~68.8% | ~5.62 MiB/s |

### Measurement Notes

- CPU values above 100% require verification of the monitoring aggregation before interpretation as normalized utilization.
- Memory charts used `state != free` with Sum aggregation. These values reflect the selected memory-state configuration, not exclusively `state = used`.
- Values were estimated visually from charts and are not exact exported measurements.
- Network throughput is reported in MiB/s.

### Verified Four-Client HTTP Responses

For the four-client test interval:

```text
2026-10-14 01:30:20 UTC
to
2026-10-14 01:33:27 UTC
```

The server journal returned:

```text
10689 200
```

This confirms **10,689 successful HTTP 200 responses** during the four-client stress-test window.

No other HTTP status appeared in the displayed server-log summary.

Client-side timeouts or connection failures that never reached the server were not independently ruled out.

Therefore, the available evidence does not establish a definitive server saturation threshold within the permitted four-client limit.

---

## 13. Performance Analysis

### CPU Utilization

The displayed CPU utilization increased between one and three concurrent clients.

The three-client run showed a higher reported peak than the four-client run.

This behavior may reflect workload variability, CPU scheduling, and monitoring alignment.

Because some displayed values exceed 100%, they should not be interpreted as normalized per-instance utilization without further metric validation.

### Memory Utilization

The selected memory measurements varied across tests rather than increasing consistently.

Possible contributing factors include:

- Operating system caching
- Memory allocation and release
- Python process activity
- Background system processes

Memory utilization did not demonstrate a consistent linear relationship with client concurrency.

### Network Bandwidth

Outgoing network throughput increased as the number of concurrent clients increased.

| Clients | Outgoing Bandwidth |
|---|---|
| 1 | ~2.15 MiB/s |
| 2 | ~3.23 MiB/s |
| 3 | ~4.70 MiB/s |
| 4 | ~5.62 MiB/s |

Higher concurrency allowed more overlapping file requests, increasing the volume of HTTP response data transferred by the server.

### Saturation Findings

The web server was tested with the maximum permitted four concurrent clients.

During the four-client round, the server journal recorded 10,689 successful HTTP 200 responses.

The recorded server-side data did not demonstrate a definitive saturation threshold.

The experiment therefore reports observed peak resource usage over the three-minute testing periods rather than claiming a confirmed overload point.

---

## 14. Google Cloud Cost Analysis

Google Cloud Billing was reviewed for **October 7–13, 2026**.

### Reported Billing Summary

| Billing Metric | Amount |
|---|---:|
| Reported usage cost | $0.02 |
| Applied savings | $0.02 |
| Net billed cost | $0.00 |

The Google Cloud billing dashboard displayed:

```text
Usage Cost: $0.02
Savings:    $0.02
----------------
Net Cost:   $0.00
```

### Resources Used

The experiment involved:

- Two e2-micro instances
- One e2-small instance
- Persistent boot disks
- Static external IP
- Google Cloud Storage
- Cloud Logging
- Cloud Monitoring
- Pub/Sub
- HTTP network traffic

### Cost Interpretation

The observed net billed cost for the selected seven-day period was **$0.00 after $0.02 in savings**.

However, this billing snapshot covers October 7–13 and does not isolate the exact cost of HW4 stress testing.

Google Cloud billing data may also be reported with a delay.

Therefore, the values above represent the available billing dashboard snapshot rather than a finalized standalone stress-test cost.

---

## 15. Security Considerations

The system uses dedicated service accounts to reduce unnecessary privileges.

Security features include:

- IAM-based access to Cloud Storage
- Separate identities for the web server and reporting service
- Scoped Pub/Sub publishing and subscription permissions
- Structured security-event logging
- No embedded service-account JSON credentials
- Restricted access to application source objects under `hw4-code/`

The server accepts HTTP traffic on port 8080 for assignment demonstrations.

For a production application, HTTPS, stricter network access, trusted IP geolocation, and stronger request validation would be appropriate.

---

## 16. Resource Cleanup

Google Compute Engine resources should be deleted when the experiment is complete to avoid ongoing charges.

### Delete Virtual Machines

```bash
gcloud compute instances delete \
  hw4-server hw4-client hw4-reporter \
  --zone=us-central1-a
```

### Release Static IP

```bash
gcloud compute addresses delete \
  hw4-server-ip \
  --region=us-central1
```

### Delete HTTP Firewall Rule

```bash
gcloud compute firewall-rules delete \
  hw4-allow-http
```

### Delete Pub/Sub Resources (Optional)

```bash
gcloud pubsub subscriptions delete hw4-forbidden-sub

gcloud pubsub topics delete hw4-forbidden
```

The existing Storage bucket should be preserved because it contains files reused from HW2 and HW3.

---

## 17. Conclusion

This project successfully implemented an HTTP file server on Google Compute Engine using Python.

The application demonstrates HTTP request processing, integration with Google Cloud Storage, structured error logging, simulated restricted-country reporting, and automated VM service startup.

The official HTTP client successfully performed a verified 100-request test, with all 100 recorded responses returning HTTP 200.

The server was subsequently tested using one through four concurrent HTTP clients over approximately three-minute intervals.

The maximum-concurrency test recorded **10,689 successful HTTP 200 responses**, while outgoing network bandwidth increased from approximately 2.15 MiB/s to 5.62 MiB/s between one and four clients.

The project also demonstrates infrastructure monitoring and cost analysis using Google Cloud's management tools.

Overall, HW4 provides practical experience deploying, operating, monitoring, and testing virtual-machine-based cloud services.

---

**CS528 — Homework 4**  
**Google Cloud Compute Engine | Python HTTP Server | Cloud Storage | Cloud Logging | Pub/Sub | Stress Testing**

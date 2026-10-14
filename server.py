#!/usr/bin/env python3
"""CS528 HW4 - Google Cloud Storage-backed HTTP server."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit, parse_qs
from google.cloud import storage, logging as cloud_logging, pubsub_v1
from google.api_core.exceptions import NotFound

PROJECT = os.environ['PROJECT_ID']
BUCKET = os.environ['BUCKET']
TOPIC = os.environ.get('TOPIC', 'hw4-forbidden')
PORT = int(os.environ.get('PORT', '8080'))
BLOCKED = {'KP','IR','CU','MM','IQ','LY','SD','ZW','SY'}
storage_client = storage.Client(project=PROJECT)
log = cloud_logging.Client(project=PROJECT).logger('hw4-http')
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT, TOPIC)

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def respond(self, status, data=b'', ctype='text/plain; charset=utf-8'):
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        if data:
            self.wfile.write(data)

    def event(self, severity, reason, **fields):
        payload = {'reason': reason, 'method': self.command, 'path': self.path,
                   'remote_addr': self.client_address[0], **fields}
        log.log_struct(payload, severity=severity)

    def get_object_name(self):
        if self.command == 'GET':
            return unquote(urlsplit(self.path).path.lstrip('/'))
        length = int(self.headers.get('Content-Length', '0'))
        if length > 8192:
            raise ValueError('Payload too large')
        payload = self.rfile.read(length).decode('utf-8')
        ctype = self.headers.get('Content-Type', '').split(';')[0]
        if ctype == 'application/json':
            body = json.loads(payload)
            return str(body.get('file') or body.get('filename') or body.get('path') or '')
        if ctype == 'application/x-www-form-urlencoded':
            return parse_qs(payload).get('file', [''])[0]
        return payload.strip()

    def serve_file(self):
        # Header-driven country simulation is for the assignment demo only.
        # A real geographic check requires a trusted IP-to-country lookup.
        country = self.headers.get('X-Country-Code', '').strip().upper()
        if country in BLOCKED:
            event = {'country': country, 'ip': self.client_address[0],
                     'path': self.path, 'method': self.command}
            self.event('CRITICAL', 'forbidden_country', country=country)
            try:
                publisher.publish(topic_path, json.dumps(event).encode('utf-8')).result(timeout=10)
            except Exception as exc:
                self.event('ERROR', 'publish_failed', error=str(exc))
            self.respond(400, b'Permission denied: forbidden country\n')
            return
        try:
            name = self.get_object_name()
            if not name or name.startswith('hw4-code/'):
                raise NotFound('Object unavailable')
            blob = storage_client.bucket(BUCKET).blob(name)
            data = blob.download_as_bytes()
            self.respond(200, data, 'application/octet-stream')
        except (NotFound, ValueError, json.JSONDecodeError) as exc:
            self.event('WARNING', 'file_not_found', error=str(exc))
            self.respond(404, b'File not found\n')
        except Exception as exc:
            self.event('ERROR', 'server_failure', error=str(exc))
            self.respond(500, b'Internal server error\n')

    def do_GET(self): self.serve_file()
    def do_POST(self): self.serve_file()

    def unsupported(self):
        self.event('ERROR', 'unsupported_method')
        self.respond(501, b'Method not implemented\n')

    do_PUT = unsupported
    do_DELETE = unsupported
    do_HEAD = unsupported
    do_CONNECT = unsupported
    do_OPTIONS = unsupported
    do_TRACE = unsupported
    do_PATCH = unsupported

if __name__ == '__main__':
    print(f'Listening on 0.0.0.0:{PORT}, bucket={BUCKET}', flush=True)
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()

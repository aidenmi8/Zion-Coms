#!/usr/bin/env bash
set -euo pipefail

python3 - "${1:-deploy/compose/compose.yml}" <<'PY'
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time

compose_file = Path(sys.argv[1])
compose_values = {
    'BUZZ_S3_ACCESS_KEY': 'test-access-key',
    'BUZZ_S3_SECRET_KEY': 'test-secret-key',
    'POSTGRES_PASSWORD': 'test-postgres-password',
    'REDIS_PASSWORD': 'test-redis-password',
}
with tempfile.TemporaryDirectory() as fixture_dir:
    fixture_path = Path(fixture_dir)
    fixture_compose = fixture_path / 'compose.yml'
    fixture_compose.write_text(compose_file.read_text())
    (fixture_path / '.env').write_text(
        ''.join(f'{name}={value}\n' for name, value in compose_values.items())
    )
    rendered = subprocess.run(
        [
            'docker',
            'compose',
            '-f',
            str(fixture_compose),
            'config',
            '--format',
            'json',
        ],
        check=True,
        capture_output=True,
        env=os.environ,
        text=True,
    )
healthcheck = json.loads(rendered.stdout)['services']['relay']['healthcheck']['test'][1]
# Compose keeps $$ escaped in `config` output but passes a literal $ to the
# container command, so exercise the exact shell program the relay receives.
runtime_healthcheck = healthcheck.replace('$$', '$')

def run_probe(response):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 0))
    listener.listen(1)
    port = listener.getsockname()[1]

    def respond():
        connection, _ = listener.accept()
        with connection:
            connection.recv(4096)
            if response is None:
                time.sleep(10)
            else:
                connection.sendall(response)

    threading.Thread(target=respond, daemon=True).start()
    command = runtime_healthcheck.replace('127.0.0.1/8080', f'127.0.0.1/{port}', 1)
    probe = subprocess.Popen(['bash', '-c', command], start_new_session=True)
    started = time.monotonic()

    try:
        exit_code = probe.wait(timeout=2.7)
    except subprocess.TimeoutExpired:
        os.killpg(probe.pid, 9)
        raise SystemExit('readiness probe did not exit when its response stalled')
    finally:
        listener.close()

    return exit_code, time.monotonic() - started

stalled_exit, stalled_elapsed = run_probe(None)
if stalled_exit == 0:
    raise SystemExit('readiness probe accepted a stalled response')
if stalled_elapsed >= 2.7:
    raise SystemExit(f'readiness probe exceeded its response deadline: {stalled_elapsed:.2f}s')

success_exit, _ = run_probe(b'HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n')
if success_exit != 0:
    raise SystemExit(
        'readiness probe rejected a 200 OK response after Compose interpolation: '
        f'{runtime_healthcheck}'
    )
PY

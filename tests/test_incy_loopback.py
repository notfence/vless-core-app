import contextlib
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
BUILD = Path(os.environ.get("VC_HOST_BUILD_DIR", ROOT / "build/host-tests"))
TOOL = BUILD / "test_incy"
PROFILE = "trojan://test%2Bpass@example.test:443?security=tls#Loopback"


def tool(mode, value):
    result = subprocess.run([str(TOOL), mode], input=value, text=True, capture_output=True, timeout=10)
    if result.returncode:
        raise AssertionError("INCY test helper rejected fixture")
    return result.stdout


class Handler(http.server.BaseHTTPRequestHandler):
    paths = []

    def do_GET(self):
        self.paths.append(self.path)
        body = PROFILE.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("profile-title", "Loopback provider")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


@contextlib.contextmanager
def server(certificate=None, key=None):
    instance = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    instance.daemon_threads = True
    if certificate:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        instance.socket = context.wrap_socket(instance.socket, server_side=True)
    worker = threading.Thread(target=instance.serve_forever, daemon=True)
    worker.start()
    try:
        yield instance.server_port
    finally:
        instance.shutdown()
        instance.server_close()
        worker.join(timeout=3)


def fetch(link, allow_http=False, certificate=None):
    descriptor = json.loads(tool("--prepare", link))
    url = descriptor["value"]
    if url.startswith("http://") and not allow_http:
        return None, "confirmation"
    command = ["curl", "--silent", "--show-error", "--fail", "--noproxy", "*",
               "--connect-timeout", "2", "--max-time", "3", "--config", "-"]
    if certificate:
        command += ["--cacert", str(certificate)]
    response = subprocess.run(command, input="url = " + json.dumps(url) + "\n",
                              capture_output=True, text=True, timeout=5)
    return response.stdout, response.returncode


with tempfile.TemporaryDirectory(prefix="incy-loopback-", dir=ROOT / "build") as temporary:
    directory = Path(temporary)
    certificate, key = directory / "cert.pem", directory / "key.pem"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1",
                    "-keyout", str(key), "-out", str(certificate)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
    os.chmod(key, 0o600)
    for secure in (False, True):
        with server(certificate if secure else None, key if secure else None) as port:
            scheme = "https" if secure else "http"
            url = f"{scheme}://127.0.0.1:{port}/sub?token=a+b%2B%2540&x=%26"
            link = tool("--wrap", json.dumps({"v": 1, "url": url, "n": "Provider 🇳🇱"}))
            before = len(Handler.paths)
            body, status = fetch(link)
            if secure:
                if status != 60:
                    raise AssertionError("INCY fixture bypassed certificate verification")
            elif status != "confirmation":
                raise AssertionError("INCY fixture bypassed HTTP confirmation")
            if len(Handler.paths) != before:
                raise AssertionError("INCY fixture fetched before security approval")
            source = {"url": link, "name": "Provider 🇳🇱", "custom_name": "Mine", "items": []}
            for _ in range(2):
                body, status = fetch(source["url"], allow_http=not secure, certificate=certificate if secure else None)
                if status or body != PROFILE:
                    raise AssertionError("INCY loopback fetch damaged subscription")
                updated = json.loads(tool("--update", json.dumps({"source": source, "body": body, "title": "Changed provider"})))
                if updated["url"] != link or updated["name"] != "Mine" or updated["items"] != [PROFILE]:
                    raise AssertionError("INCY update damaged source or rename")
                source = json.loads(json.dumps(updated))
            if Handler.paths[-2:] != ["/sub?token=a+b%2B%2540&x=%26"] * 2:
                raise AssertionError("INCY loopback changed URL encoding")
            print("PASS INCY loopback:", "HTTPS trust and update" if secure else "HTTP confirmation and update")

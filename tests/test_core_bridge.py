import contextlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

APP = Path(__file__).resolve().parents[1]
CORE = APP.parent / "vless-core-cli"
BUILD = Path(os.environ.get("VC_HOST_BUILD_DIR", APP / "build/host-tests"))
CORE_BUILD = BUILD / "core-cli"

command = ["make", "-C", str(CORE / "tests"), "-j4", str(CORE_BUILD / "vless-core-test"),
           f"HOST_BUILD_DIR={CORE_BUILD}", "HOST_CC=/usr/bin/clang", f"SANITIZE={os.environ.get('VC_TEST_SANITIZE', '')}"]
subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
os.environ["TEST_BUILD_DIR"] = str(CORE_BUILD)
os.environ["TEST_XRAY_BIN"] = str(APP.parent / "tools/xray-v26.6.27-linux-64/xray")
private_parent = Path.home() / ".local/state"
private_parent.mkdir(mode=0o700, parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="vless-app-bridge-", dir=private_parent) as private:
    os.environ["TEST_PRIVATE_ROOT"] = private
    sys.path.insert(0, str(CORE / "tests"))
    import fixtures as f

    encryption = f"mlkem768x25519plus.native.0rtt.{f.PUBLIC_KEY}"
    decryption = f"mlkem768x25519plus.native.600s.{f.KEY}"
    flow = "xtls-rprx-vision"
    cert, _ = f.certificate()
    for transport, security in (("tcp", "none"), ("ws", "tls"), ("grpc", "tls"), ("xhttp", "reality")):
        shared = {"sessionIDPlacement": "header", "sessionIDKey": "X-vless-core-session", "seqPlacement": "header"}
        with contextlib.ExitStack() as stack:
            target = stack.enter_context(f.Server())
            options = {"path": "/", **shared} if transport == "xhttp" else {}
            reference = stack.enter_context(f.xray_server(transport, security, mode="multi" if transport == "grpc" else None,
                                                         flow=flow, decryption=decryption, **options))
            stream = {"network": transport, "security": security}
            endpoint = reference.port
            pins = []
            if security == "tls":
                stream["tlsSettings"] = {"serverName": "vless-core.test", "fingerprint": "firefox"}
            elif security == "reality":
                stream["realitySettings"] = {"serverName": "vless-core.test", "publicKey": f.PUBLIC_KEY,
                                             "shortId": "01020304", "fingerprint": "firefox"}
            if transport == "ws":
                stream["wsSettings"] = {"path": "/vless-core?ed=64", "maxEarlyData": 16384, "heartbeatPeriod": 1,
                                        "headers": {"X-Vless-Core": "bridge"}}
            elif transport == "grpc":
                stream["grpcSettings"] = {"serviceName": "vless-core", "multi_mode": True, "idle_timeout": 1,
                                          "health_check_timeout": 20, "permit_without_stream": False,
                                          "initial_windows_size": 65536, "user_agent": "vless-core"}
            elif transport == "xhttp":
                upload = stack.enter_context(f.CountingProxy(reference.port))
                download = stack.enter_context(f.CountingProxy(reference.port, address="127.0.0.2"))
                endpoint = upload.port
                down = {"address": "download.invalid", "port": download.port, "network": "xhttp", "security": security,
                        "realitySettings": dict(stream["realitySettings"]), "xhttpSettings": {"path": "/download", **shared}}
                stream["xhttpSettings"] = {"path": "/upload", "mode": "stream-up",
                                           "extra": {"downloadSettings": down, "xmux": {"maxConnections": 1}, **shared}}
                pins = ["--server-ips", "127.0.0.1", "--download-server-ips", "127.0.0.3,127.0.0.2"]
            config = {"outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": "127.0.0.1", "port": endpoint,
                       "users": [{"id": f.UUID, "encryption": encryption, "flow": flow}]}]}, "streamSettings": stream}]}
            result = subprocess.run([str(BUILD / "test_import_formats"), "--convert"], input=json.dumps(config),
                                    text=True, capture_output=True, timeout=5)
            if result.returncode or len(result.stdout.splitlines()) != 1:
                raise AssertionError(f"HAPP conversion failed for {transport}: {result.stderr}")
            uri = result.stdout.strip()
            inspected = subprocess.run([str(BUILD / "test_core_config"), "--real", str(CORE_BUILD / "vless-core-test")],
                                       input=uri, text=True, capture_output=True, timeout=5)
            if inspected.returncode or "PRIMARY\t127.0.0.1\t" not in inspected.stdout:
                raise AssertionError(f"inspection failed for {transport}: {inspected.stderr}")
            if transport == "xhttp" and "DOWNLOAD\tdownload.invalid\t" not in inspected.stdout:
                raise AssertionError("download metadata was lost")
            with f.cli(uri, extra=pins, environment={"VLESS_CA_BUNDLE": str(cert)}) as client:
                for index in range(3):
                    with f.socks_connect(client.port, target.port) as connection:
                        f.exchange(connection, bytes(range(256)) * 4096 + bytes([index]))
            if transport == "xhttp" and (not upload.client_data or not download.client_data):
                raise AssertionError("independent XHTTP channel was not used")
            print(f"PASS HAPP/core/Xray: {transport}/{security}")

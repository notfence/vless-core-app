import contextlib
import base64
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
version = subprocess.run([str(CORE_BUILD / "vless-core-test"), "--version"], capture_output=True, text=True, timeout=5, check=True).stdout.strip()
if not version.startswith("vless-core 2.0.0 (") or not version.endswith(")"):
    raise AssertionError("unexpected current core version format")
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
            karing = {"type": "vless", "server": "127.0.0.1", "server_port": endpoint,
                      "uuid": f.UUID, "encryption": encryption, "flow": flow,
                      "transport": {"type": transport},
                      "tls": {"enabled": security != "none", "server_name": "vless-core.test",
                              "utls": {"fingerprint": "firefox"}}}
            if security == "reality":
                karing["tls"]["reality"] = {"enabled": True, "public_key": f.PUBLIC_KEY, "short_id": "01020304"}
            if transport != "tcp":
                karing["transport"].update(stream[{"ws": "wsSettings", "grpc": "grpcSettings", "xhttp": "xhttpSettings"}[transport]])
            converted = subprocess.run([str(BUILD / "test_import_formats"), "--convert-karing"], input=json.dumps(karing),
                                       text=True, capture_output=True, timeout=5)
            if converted.returncode or len(converted.stdout.splitlines()) != 1:
                raise AssertionError(f"Karing conversion failed for {transport}: {converted.stderr}")
            karing_uri = converted.stdout.strip()
            inspected = subprocess.run([str(BUILD / "test_core_config"), "--real", str(CORE_BUILD / "vless-core-test")],
                                       input=uri, text=True, capture_output=True, timeout=5)
            if inspected.returncode or "PRIMARY\t127.0.0.1\t" not in inspected.stdout:
                raise AssertionError(f"inspection failed for {transport}: {inspected.stderr}")
            if transport == "xhttp" and "DOWNLOAD\tdownload.invalid\t" not in inspected.stdout:
                raise AssertionError("download metadata was lost")
            for source, connection_uri in (("HAPP", uri), ("Karing", karing_uri)):
                with f.cli(connection_uri, extra=pins, environment={"VLESS_CA_BUNDLE": str(cert)}) as client:
                    for index in range(3):
                        with f.socks_connect(client.port, target.port) as connection:
                            f.exchange(connection, bytes(range(256)) * 4096 + bytes([index]))
                print(f"PASS {source}/core/Xray: {transport}/{security}")
            if transport == "xhttp" and (not upload.client_data or not download.client_data):
                raise AssertionError("independent XHTTP channel was not used")
            print(f"PASS HAPP/core/Xray: {transport}/{security}")

    protocols = [("trojan", None), ("vmess", None)] + [("shadowsocks", method) for method in f.SHADOWSOCKS_METHODS]
    cases = [("tcp", s, None, False) for s in ("none", "tls", "reality")]
    cases += [("ws", s, None, False) for s in ("none", "tls")]
    cases += [("grpc", s, mode, False) for s in ("none", "tls", "reality") for mode in ("gun", "multi")]
    cases += [("xhttp", s, mode, False) for s in ("none", "tls", "reality") for mode in ("stream-one", "stream-up", "packet-up")]
    cases += [("xhttp", "tls", "stream-up", True)]
    for protocol, method in protocols:
        for transport, security, mode, separate in cases:
            with contextlib.ExitStack() as stack:
                target = stack.enter_context(f.Server())
                password = f.shadowsocks_password(method) if method else f.TROJAN_PASSWORD
                shared = {"sessionIDPlacement": "header", "sessionIDKey": "X-vless-core-session", "seqPlacement": "header"}
                options = {"path": "/", **shared} if transport == "xhttp" else {}
                reference = stack.enter_context(f.xray_server(transport, security, mode=mode, protocol=protocol,
                                                             password=password, ss_method=method or "aes-128-gcm", **options))
                stream = {"network": transport, "security": security}
                if security == "tls":
                    stream["tlsSettings"] = {"serverName": "vless-core.test", "fingerprint": "firefox"}
                elif security == "reality":
                    stream["realitySettings"] = {"serverName": "vless-core.test", "publicKey": f.PUBLIC_KEY,
                                                 "shortId": "01020304", "fingerprint": "firefox"}
                settings_key = {"ws": "wsSettings", "grpc": "grpcSettings", "xhttp": "xhttpSettings"}.get(transport)
                pins = ["--server-ips", "127.0.0.1"]
                endpoint = reference.port
                if transport == "ws":
                    stream[settings_key] = {"path": "/vless-core?ed=64", "maxEarlyData": 16384,
                                            "heartbeatPeriod": 1, "headers": {"X-Fixture": "bridge"}}
                elif transport == "grpc":
                    stream[settings_key] = {"serviceName": "vless-core", "multiMode": mode == "multi"}
                elif transport == "xhttp":
                    extra = {"xmux": {"maxConnections": 2, "maxConcurrency": ""}, **shared}
                    stream[settings_key] = {"path": "/", "mode": mode, "extra": extra}
                    if separate:
                        upload = stack.enter_context(f.CountingProxy(reference.port))
                        download = stack.enter_context(f.CountingProxy(reference.port, address="127.0.0.2"))
                        endpoint = upload.port
                        extra["downloadSettings"] = {"address": "download.invalid", "port": download.port,
                            "network": "xhttp", "security": security, "tlsSettings": dict(stream["tlsSettings"]),
                            "xhttpSettings": {"path": "/download", **shared}}
                        stream[settings_key]["path"] = "/upload"
                        pins += ["--download-server-ips", "127.0.0.3,127.0.0.2"]
                settings = {"address": "primary.invalid", "port": endpoint, "password": password}
                if protocol == "vmess":
                    settings = {"vnext": [{"address": "primary.invalid", "port": endpoint,
                                           "users": [{"id": f.UUID, "security": "chacha20-poly1305", "alterId": 0}]}]}
                elif protocol == "shadowsocks":
                    settings["method"] = method
                happ = {"outbounds": [{"protocol": protocol, "settings": settings, "streamSettings": stream}]}
                karing = {"type": protocol, "server": "primary.invalid", "server_port": endpoint,
                          "password": password, "uuid": f.UUID,
                          "tls": {"enabled": security != "none", "server_name": "vless-core.test", "utls": {"fingerprint": "firefox"}},
                          "transport": {"type": transport, **stream.get(settings_key, {})}}
                if protocol == "vmess":
                    karing.update(security="chacha20-poly1305", alter_id=0)
                if method:
                    karing["method"] = method
                if security == "reality":
                    karing["tls"]["reality"] = {"enabled": True, "public_key": f.PUBLIC_KEY, "short_id": "01020304"}
                for source, document, option in (("HAPP", happ, "--convert"), ("Karing", karing, "--convert-karing")):
                    converted = subprocess.run([str(BUILD / "test_import_formats"), option], input=json.dumps(document),
                                               text=True, capture_output=True, timeout=5)
                    if converted.returncode or len(converted.stdout.splitlines()) != 1:
                        raise AssertionError(f"{protocol}/{source}/{transport}/{security}/{mode}: conversion failed")
                    uri = converted.stdout.strip()
                    inspected = subprocess.run([str(BUILD / "test_core_config"), "--real", str(CORE_BUILD / "vless-core-test")],
                                               input=uri, text=True, capture_output=True, timeout=5)
                    if inspected.returncode or "PRIMARY\tprimary.invalid\t" not in inspected.stdout:
                        raise AssertionError(f"{protocol}/{source}: offline inspection failed")
                    if separate and "DOWNLOAD\tdownload.invalid\t" not in inspected.stdout:
                        raise AssertionError(f"{protocol}/{source}: missing download endpoint")
                    with f.cli(uri, extra=pins, environment={"VLESS_CA_BUNDLE": str(cert)}) as client:
                        for index in range(2):
                            with f.socks_connect(client.port, target.port) as connection:
                                f.exchange(connection, b"\x00\x00" + bytes(range(256)) * 256 + bytes([index]))
                    if separate and (not upload.client_data or not download.client_data):
                        raise AssertionError(f"{protocol}/{source}: separate channel was not used")
                print(f"PASS app/core/Xray: {protocol}/{method or '-'}/{transport}/{security}/{mode}/download={separate}")

    for method in ("2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm"):
        size = 16 if method.endswith("128-gcm") else 32
        keys = [base64.b64encode(bytes(range(i, i + size))).decode() for i in range(3)]
        for count in (2, 3):
            with contextlib.ExitStack() as stack:
                target = stack.enter_context(f.Server())
                leaf = stack.enter_context(f.xray_server("tcp", "none", protocol="shadowsocks", ss_method=method,
                    password=keys[count - 2], ss_users=[{"password": keys[count - 1]}]))
                reference = leaf if count == 2 else stack.enter_context(f.xray_server("tcp", "none", protocol="shadowsocks",
                    ss_method=method, password=keys[0], ss_users=[{"password": keys[1], "address": "127.0.0.1", "port": leaf.port}]))
                settings = {"address": "127.0.0.1", "port": reference.port, "method": method, "password": ":".join(keys[:count])}
                happ = {"outbounds": [{"protocol": "shadowsocks", "settings": settings}]}
                karing = {"type": "shadowsocks", "server": "127.0.0.1", "server_port": reference.port,
                          "method": method, "password": settings["password"]}
                for document, option in ((happ, "--convert"), (karing, "--convert-karing")):
                    converted = subprocess.run([str(BUILD / "test_import_formats"), option], input=json.dumps(document),
                                               text=True, capture_output=True, timeout=5, check=True)
                    with f.cli(converted.stdout.strip()) as client:
                        with f.socks_connect(client.port, target.port) as connection:
                            f.exchange(connection, b"\x00\x00SIP023" + bytes(range(256)) * 256)
                print(f"PASS app/core/Xray: SIP023/{method}/{count}")

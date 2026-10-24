import argparse
import gzip
import io
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
CHECKS = 0
LAUNCHES = {
    "Default.png": (320, 480), "Default@2x.png": (640, 960),
    "Default~iphone.png": (320, 480), "Default@2x~iphone.png": (640, 960),
    "Default-568h@2x.png": (640, 1136), "Default-667h@2x.png": (750, 1334),
    "Default-736h@3x.png": (1242, 2208), "Default-Portrait~ipad.png": (768, 1004),
    "Default-Portrait@2x~ipad.png": (1536, 2008), "Default-Landscape~ipad.png": (1024, 748),
    "Default-Landscape@2x~ipad.png": (2048, 1496),
}
BINARIES = {
    "Applications/vless-core.app/vless-core": (12, 5, 0o755),
    "Applications/vless-core.app/vless-core-arm64": (0x100000C, 11, 0o755),
    "usr/bin/vpnctld": (12, 5, 0o755), "usr/bin/vpnctld-arm64": (0x100000C, 11, 0o755),
    "usr/bin/vpnctld-bootstrap": (12, 5, 0o4755), "usr/bin/vpnctld-bootstrap-arm64": (0x100000C, 11, 0o755),
    "usr/bin/vless-core-darwin-armv7": (12, 5, 0o755), "usr/bin/vless-core-darwin-arm64": (0x100000C, 11, 0o755),
    "usr/bin/vless-core-curl": (12, 5, 0o755), "usr/bin/vless-core-curl-arm64": (0x100000C, 11, 0o755),
    "usr/bin/redsocks-vless-core": (12, 5, 0o755), "usr/bin/redsocks-vless-core-arm64": (0x100000C, 11, 0o755),
}

def check(name, condition):
    global CHECKS
    if not condition:
        raise AssertionError(name)
    CHECKS += 1

def control_fields(data):
    return dict(line.split(": ", 1) for line in data.decode().splitlines() if ": " in line)

def png_contract(name, data):
    check(f"launch/{name}/png", data[:8] == b"\x89PNG\r\n\x1a\n")
    offset = 8
    types = []
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        check(f"launch/{name}/crc/{kind.decode()}", zlib.crc32(kind + payload) == crc)
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            check(f"launch/{name}/dimensions", (width, height) == LAUNCHES[name])
            check(f"launch/{name}/opaque-format", color in (0, 2) and depth in (8, 16))
            check(f"launch/{name}/noninterlaced", compression == filtering == interlace == 0)
        types.append(kind)
        offset += length + 12
    check(f"launch/{name}/complete", b"IDAT" in types and types[-1] == b"IEND" and offset == len(data))
    check(f"launch/{name}/no-transparent-key", b"tRNS" not in types)

def source_contracts():
    sys.dont_write_bytecode=True
    from test_flag_assets import validate
    validate()
    info = plistlib.loads((ROOT / "app/Info.plist").read_bytes())
    control = control_fields((ROOT / "packaging/DEBIAN/control").read_bytes())
    check("plist/minimum-ios-5.0", info["MinimumOSVersion"] == "5.0")
    check("package/firmware-5.0", control["Depends"] == "firmware (>= 5.0)")
    check("package/version-consistency", control["Version"].split("-")[0] == info["CFBundleShortVersionString"])
    check("package/architecture-contract", control["Architecture"] == "iphoneos-arm")
    check("plist/bundle-identity", info["CFBundleIdentifier"] == "com.vlesscore.app" and info["CFBundleExecutable"] == "vless-core")
    check("plist/device-families", info["UIDeviceFamily"] == [1, 2])
    for key in ("UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"):
        check(f"plist/{key}/both-landscapes", {"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}.issubset(info[key]))
    check("plist/camera-usage", bool(info["NSCameraUsageDescription"]))
    check("plist/launch-catalog", {entry["UILaunchImageName"] for entry in info["UILaunchImages"]} == {"Default", "Default-568h", "Default-667h", "Default-736h", "Default-Portrait", "Default-Landscape"})
    for name in LAUNCHES:
        png_contract(name, (ROOT / "app/icons" / name).read_bytes())
    launchd = plistlib.loads((ROOT / "packaging/Library/LaunchDaemons/com.vlesscore.vpnctld.plist").read_bytes())
    check("launchd/executable", launchd["ProgramArguments"][0] == "/usr/bin/vpnctld")
    for script in ("postinst", "prerm", "postrm"):
        result = subprocess.run(["/bin/sh", "-n", str(ROOT / "packaging/DEBIAN" / script)], capture_output=True)
        check(f"installer/{script}/shell-syntax", result.returncode == 0)

def installer_contracts(major):
    with tempfile.TemporaryDirectory(prefix="vless-host-installer-") as temporary:
        base = Path(temporary)
        fake_root, mock_bin, trace = base / "root", base / "bin", base / "trace"
        mock_bin.mkdir()
        def executable(path, text):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            path.chmod(0o755)
        for name in ("chown", "launchctl", "killall", "sleep", "uicache", "su", "id", "sync"):
            body = 'printf "%s\\n" "' + name + ' $*" >>"$VC_TEST_INSTALL_TRACE"\n'
            if name == "killall": body += '[ "$1" != -0 ]\n'
            if name == "launchctl": body += '[ "$1" != list ]\n'
            executable(mock_bin / name, "#!/bin/sh\n" + body)
        executable(fake_root / "usr/bin/sw_vers", f"#!/bin/sh\nprintf '%s\\n' '{major}.0'\n")
        for path in BINARIES:
            label = "arm64" if "arm64" in path else "armv7"
            executable(fake_root / path, f"#!/bin/sh\nprintf '%s\\n' '{label} $*' >>\"$VC_TEST_INSTALL_TRACE\"\n")
        for path in ("usr/share/vless-core", "var/log", "var/run", "var/db/vless-core", "Library/LaunchDaemons"):
            (fake_root / path).mkdir(parents=True, exist_ok=True)
        (fake_root / "usr/share/vless-core/openssl-patch-status").write_text("armv7")
        (fake_root / "usr/share/vless-core/openssl-patch-status-arm64").write_text("arm64")
        (fake_root / "Library/LaunchDaemons/com.vlesscore.vpnctld.plist").write_bytes((ROOT / "packaging/Library/LaunchDaemons/com.vlesscore.vpnctld.plist").read_bytes())
        environment = dict(os.environ, PATH=f"{mock_bin}:/usr/bin:/bin", VC_TEST_INSTALL_TRACE=str(trace))
        def invoke(name, action):
            source = (ROOT / "packaging/DEBIAN" / name).read_text()
            translated = re.sub(r"(?<![A-Za-z0-9_.-])/(Applications|Library|usr|var|private|System)(?=/)", lambda match: str(fake_root) + match[0], source)
            result = subprocess.run(["/bin/sh", "-s", action], input=translated, text=True, env=environment, capture_output=True, timeout=10)
            return result
        result = invoke("postinst", "configure")
        check(f"installer/ios{major}/configure", result.returncode == 0)
        expected = "arm64" if major >= 11 else "armv7"
        check(f"installer/ios{major}/runtime-selection", (fake_root / "usr/share/vless-core/runtime-architecture").read_text().strip() == expected)
        check(f"installer/ios{major}/bootstrap-setuid", stat.S_IMODE((fake_root / "usr/bin/vpnctld-bootstrap").stat().st_mode) == 0o4755)
        check(f"installer/ios{major}/private-imports", stat.S_IMODE((fake_root / "var/mobile/vless-core-import").stat().st_mode) == 0o700)
        check(f"installer/ios{major}/selected-app", expected in (fake_root / "Applications/vless-core.app/vless-core").read_text())
        check(f"installer/ios{major}/unneeded-core-removed", not (fake_root / ("usr/bin/vless-core-darwin-armv7" if major >= 11 else "usr/bin/vless-core-darwin-arm64")).exists())
        stale = fake_root / "var/db/vless-core/pf-state"
        stale.write_text("foreign network state must survive")
        result = invoke("prerm", "upgrade")
        check(f"installer/ios{major}/refuse-unrestored-network", result.returncode == 1 and stale.exists())
        stale.unlink()
        check(f"installer/ios{major}/remove-after-cleanup", invoke("prerm", "remove").returncode == 0)
        check(f"installer/ios{major}/postrm", invoke("postrm", "remove").returncode == 0)
        check(f"installer/ios{major}/runtime-marker-removed", not (fake_root / "usr/share/vless-core/runtime-architecture").exists())

def macho_contract(name, data, cpu, minimum):
    check(f"macho/{name}/magic", data[:4] in (b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe"))
    is64 = data[0] == 0xcf
    cputype, subtype, filetype, ncmds, sizeofcmds, flags = struct.unpack_from("<6I", data, 4)
    check(f"macho/{name}/cpu", cputype == cpu and (cpu != 12 or subtype & 0xffffff == 9))
    check(f"macho/{name}/pie", filetype == 2 and flags & 0x200000)
    offset = 32 if is64 else 28
    minos = None
    signature = None
    for _ in range(ncmds):
        command, size = struct.unpack_from("<II", data, offset)
        check(f"macho/{name}/command-bounds", size >= 8 and offset + size <= len(data))
        if command == 0x25: minos = struct.unpack_from("<I", data, offset + 8)[0]
        if command == 0x32: minos = struct.unpack_from("<I", data, offset + 12)[0]
        if command == 0x1d:
            start, length = struct.unpack_from("<II", data, offset + 8)
            signature = data[start:start + length]
        offset += size
    check(f"macho/{name}/minimum-ios", minos == minimum << 16)
    check(f"macho/{name}/signature", signature is not None and len(signature) >= 12)
    magic, length, count = struct.unpack_from(">III", signature)
    check(f"signature/{name}/superblob", magic == 0xfade0cc0 and length <= len(signature))
    slots = {}
    for i in range(count):
        slot, offset = struct.unpack_from(">II", signature, 12 + 8 * i)
        blob_length = struct.unpack_from(">I", signature, offset + 4)[0]
        slots[slot] = signature[offset:offset + blob_length]
    check(f"signature/{name}/primary-directory", 0 in slots)
    if cpu == 0x100000C:
        directory = slots[0]
        check(f"signature/{name}/sha256-primary", directory[37] == 2)
        version = struct.unpack_from(">I", directory, 8)[0]
        check(f"signature/{name}/execution-segment", version >= 0x20400 and len(directory) >= 88 and struct.unpack_from(">Q", directory, 80)[0] & 1)
        if name in ("Applications/vless-core.app/vless-core-arm64", "usr/bin/vpnctld-arm64"):
            check(f"signature/{name}/entitlements-and-der", 5 in slots and 7 in slots)

def archive_members(data):
    check("deb/ar-magic", data[:8] == b"!<arch>\n")
    offset = 8
    members = []
    while offset < len(data):
        header = data[offset:offset + 60]
        check("deb/ar-header", len(header) == 60 and header[-2:] == b"`\n")
        size = int(header[48:58])
        members.append((header[:16].decode().strip().rstrip("/"), data[offset + 60:offset + 60 + size]))
        offset += 60 + size + (size % 2)
    check("deb/member-order", [name for name, _ in members] == ["debian-binary", "control.tar.gz", "data.tar.gz"])
    check("deb/version", members[0][1] == b"2.0\n")
    return dict(members)

def deb_contract(path):
    members = archive_members(path.read_bytes())
    files = {}
    for archive_name in ("control.tar.gz", "data.tar.gz"):
        with tarfile.open(fileobj=io.BytesIO(gzip.decompress(members[archive_name])), mode="r:") as archive:
            for item in archive:
                name = item.name.removeprefix("./").rstrip("/")
                check(f"deb/{name}/root-owner", item.uid == item.gid == 0)
                check(f"deb/{name}/safe-path", not name.startswith("/") and ".." not in Path(name).parts)
                if item.isfile(): files[(archive_name, name)] = (item, archive.extractfile(item).read())
    for name, (cpu, minimum, mode) in BINARIES.items():
        check(f"deb/{name}/present", ("data.tar.gz", name) in files)
        info, data = files[("data.tar.gz", name)]
        check(f"deb/{name}/permissions", info.mode == mode)
        macho_contract(name, data, cpu, minimum)
    info = plistlib.loads(files[("data.tar.gz", "Applications/vless-core.app/Info.plist")][1])
    check("deb/ios5-and-build-metadata", info["MinimumOSVersion"] == "5.0" and info["VCBuildDate"] != "development build")
    for name in LAUNCHES: png_contract(name, files[("data.tar.gz", "Applications/vless-core.app/" + name)][1])
    flag_members={name.removeprefix("Applications/vless-core.app/flags/"):data for (archive,name),(_,data) in files.items() if archive=="data.tar.gz" and name.startswith("Applications/vless-core.app/flags/")}
    expected_flags={p.name:p.read_bytes() for p in (ROOT/"app/icons/flags").glob("*.png")}
    check("deb/flag-graphics-complete-and-identical",flag_members==expected_flags and len(flag_members)==268)
    for name in ("postinst", "prerm", "postrm"):
        item, data = files[("control.tar.gz", name)]
        check(f"deb/{name}/executable-and-current", item.mode == 0o755 and data == (ROOT / "packaging/DEBIAN" / name).read_bytes())
    check("deb/no-test-files", not any("/tests/" in name or "/host-tests/" in name for _, name in files))
    for name in ("usr/share/vless-core/cacert.pem", "Applications/vless-core.app/LICENSE", "Applications/vless-core.app/THIRD_PARTY_LICENSES.txt"):
        check(f"deb/{name}/present", ("data.tar.gz", name) in files)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--deb", type=Path)
    args = parser.parse_args()
    if args.deb:
        deb_contract(args.deb)
    else:
        source_contracts()
        for major in (5, 6, 10, 12): installer_contracts(major)
    print(f"PASS package contracts: {CHECKS} checks")

if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, OSError, ValueError, struct.error) as error:
        raise SystemExit(f"FAIL package/{error}")

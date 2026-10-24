import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    with tempfile.TemporaryDirectory(prefix="vless-preflight-") as temporary:
        root = Path(temporary)
        marker = root / "ios-compiler-called"
        compiler = root / "ios-compiler"
        compiler.write_text('#!/bin/sh\nprintf "called\\n" >>"$VC_TEST_COMPILER_MARKER"\nexit 99\n')
        compiler.chmod(0o755)
        environment = dict(os.environ, VC_TEST_FAIL_SCENARIO="connection/idle-connect-allowed", VC_TEST_COMPILER_MARKER=str(marker))
        build = root / "build"
        for target in ("app", "daemon", "deb", "tarball", str(build / "app/app/main.o"), str(build / "arm64/zbar/image.o"), str(build / "app/core-json.o"), str(build / "arm64/app/core-json.o")):
            result = subprocess.run(["make", "-j8", target, f"BUILD_DIR={build}", f"IOS_CC={compiler}"], cwd=ROOT, env=environment, capture_output=True, text=True, timeout=90)
            output = result.stdout + result.stderr
            if result.returncode == 0 or "FAIL connection/idle-connect-allowed" not in output or marker.exists():
                raise AssertionError(f"parallel-gate/{target}: {output[-4000:]}")
        missing = dict(environment)
        missing.pop("VC_TEST_FAIL_SCENARIO")
        result = subprocess.run(["make", "-j8", "app", f"BUILD_DIR={build}", f"IOS_CC={compiler}", f"HOST_PREFIX={root / 'missing-dependencies'}"], cwd=ROOT, env=missing, capture_output=True, text=True, timeout=30)
        if result.returncode == 0 or "Missing host development dependencies" not in result.stdout + result.stderr or marker.exists():
            raise AssertionError("missing-dependencies-must-fail-before-ios")
        result = subprocess.run(["make", "clean", f"BUILD_DIR={root / 'clean-case'}", f"HOST_PREFIX={root / 'missing-dependencies'}"], cwd=ROOT, env=missing, capture_output=True, text=True, timeout=30)
        if result.returncode != 0 or "Missing host development dependencies" in result.stdout + result.stderr:
            raise AssertionError("clean-must-not-run-tests")
    print("PASS preflight: parallel app/daemon/deb/tarball/direct-object gates, missing dependencies, clean")

if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"FAIL preflight/{error}")

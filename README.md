# vless-core-app

`vless-core-app` is an iOS 6–14 app + root daemon for full-device VLESS/SOCKS5 routing.

## Compatibility

- iOS 6.x through iOS 14.x
- iOS 6–10 uses the original ARMv7 runtime, including ARM64 devices through 32-bit compatibility
- iOS 11–14 uses a native ARM64 runtime
- Jailbreak required (rootful)

One `.deb` contains separate thin ARMv7 and ARM64 versions of the app, daemon,
core, and helper binaries. During installation, `postinst` selects ARM64 only on
iOS 11 or newer. It leaves the original ARMv7 implementation in the runtime
paths on iOS 6–10, even when the device itself has an ARM64 CPU.

See the [Issues](https://github.com/notfence/vless-core-app/issues) page for the current bug list.

## Install on iOS

### Install from latest release (.deb)

1. Download `.deb` from [latest release](https://github.com/notfence/vless-core-app/releases/latest).
2. Put the `.deb` file on your device (for example: `/var/mobile/`).
3. In iFile, find the `.deb`, tap it, and press `Install`.
4. Wait for `uicache` to finish. Respring is not required anymore.
5. As soon as you see “`Installation done! You can now exit the installer.`” you can exit the installer and start using app.

Also you can use terminal app to install it:
```bash
dpkg -i com.vlesscore.app_iphoneos-arm.deb
```

### Install your own build via SSH (scp + dpkg)


```bash
# on build machine
scp build/com.vlesscore.app_iphoneos-arm.deb root@<idevice-ip>:/var/root/

# on iDevice
dpkg -i com.vlesscore.app_iphoneos-arm.deb
```
## Uninstall
### Uninstall via Cydia
Just go to Cydia and remove it like usual tweak
### Uninstall via terminal/SSH
Execute this command:
```bash 
dpkg -r com.vlesscore.app
```

## Supported Protocols

Bundled core supports:

- `VLESS + TCP + Reality (+ xtls-rprx-vision)`
- `VLESS + TCP + TLS (+ xtls-rprx-vision)`
- `VLESS + TCP` (no security)
- `VLESS + XHTTP + Reality`
- `VLESS + XHTTP + TLS`
- `VLESS + XHTTP` (no security)
- `VLESS + gRPC + Reality`
- `VLESS + gRPC + TLS`
- `VLESS + gRPC` (no security)
- `VLESS + WebSocket + TLS`
- `VLESS + WebSocket` (no security)
- `SOCKS5`

`fp=chrome/firefox/edge/random/randomized/qq`

Protocol semantics are aligned with `xray-core` for the supported transports and URI parameters.

For XHTTP, `mode=auto` follows xray's defaults: `packet-up` without security or with TLS, and `stream-one` with Reality.

## Build

Need `vless-core-cli` first.

Build or download it from:

- Repo: https://github.com/notfence/vless-core-cli
- Latest release: https://github.com/notfence/vless-core-cli/releases/latest

`vless-core-app` package build expects these files:

- `../vless-core-cli/vless-core-darwin-armv7`
- `../vless-core-cli/vless-core-darwin-arm64`
- `../vless-core-cli/third_party/curl-ios6-armv7/bin/curl`
- `../vless-core-cli/third_party/curl-ios-arm64/bin/curl`
- `../vless-core-cli/third_party/cacert.pem`

Build them in `vless-core-cli`:

```bash
# build vless-core-cli assets first
cd /path/to/vless-core-cli
IOS_TOOLCHAIN=/path/to/ios6/toolchain
APP_IOS_SDK=/path/to/iPhoneOS10.3.sdk
ARM64_IOS_SDK=/path/to/iPhoneOS11.4.sdk
make openssl-ios6 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make openssl-ios-arm64 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make zlib-ios6 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make zlib-ios-arm64 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make curl-ios6 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make curl-ios-arm64 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make third_party/cacert.pem
make ios IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make ios-arm64 IOS_TOOLCHAIN=$IOS_TOOLCHAIN

# then build app package
cd /path/to/vless-core-app
make clean
make deb IOS_TOOLCHAIN=$IOS_TOOLCHAIN APP_IOS_SDK=$APP_IOS_SDK ARM64_IOS_SDK=$ARM64_IOS_SDK
```

Output:

- `build/com.vlesscore.app_iphoneos-arm.deb`
By default, package build takes binaries from sibling repo:

- `../vless-core-cli/vless-core-darwin-armv7`
- `../vless-core-cli/vless-core-darwin-arm64`
- `../vless-core-cli/third_party/curl-ios6-armv7/bin/curl`
- `../vless-core-cli/third_party/curl-ios-arm64/bin/curl`
- `../vless-core-cli/third_party/cacert.pem`

Override paths if needed:

```bash
make deb \
  VLESS_CORE_BIN=/abs/path/to/vless-core-darwin-armv7 \
  VLESS_CORE_ARM64_BIN=/abs/path/to/vless-core-darwin-arm64 \
  VLESS_CORE_CURL_BIN=/abs/path/to/curl \
  VLESS_CORE_CURL_ARM64_BIN=/abs/path/to/arm64/curl \
  CA_BUNDLE=/abs/path/to/cacert.pem
```

Package uses `gzip` compression for old iOS 6 `dpkg` compatibility.

## Runtime paths

- App: `/Applications/vless-core.app`
- Daemon API: authenticated Unix socket at `/var/run/vpnctld.sock`
- `postinst` keeps only the runtime selected for the installed iOS version and removes the other architecture
- Selected runtime: `/usr/share/vless-core/runtime-architecture`
- Core runtime path: `/usr/bin/vless-core-darwin-armv7` on iOS 6–10 or `/usr/bin/vless-core-darwin-arm64` on iOS 11+
- Subscription fetch runtime path: `/usr/bin/vless-core-curl`
- CA bundle: `/usr/share/vless-core/cacert.pem`
- Redsocks helper: `/usr/bin/redsocks-vless-core`
- Logs:
  - `/var/log/vpnctld.log`
  - `/var/log/vless-core.log`

## Full-device backend

The daemon uses `pf + redsocks` on every supported version. On iOS 11–14 it
also installs a temporary, non-persistent PAC setting that sends
CFNetwork/WebKit traffic through the local SOCKS listener, including Safari
traffic that can bypass PF. Original proxy settings are restored on disconnect,
helper failure, daemon restart, package upgrade, and package removal. The PAC
state is not written to the persistent SystemConfiguration preferences.

## License

Code owned by notfence is available under the
[`vless-core-app Source License 1.0`](LICENSE). It may be used in personal,
internal business, and unrelated income-producing activities, but the project
itself may not be sold, included in a paid product, or used to provide a paid
VPN or proxy service. Complete, unmodified source may be redistributed;
private modification and compilation by individuals are permitted; legal
entities may use official builds but may not create private modifications.
Modified source and unofficial build artifacts may not be distributed.
Byte-for-byte identical official artifacts may be redistributed without
payment and with their notices.

## Third-party software

Third-party licenses apply only to the components identified in
[`legal/THIRD_PARTY_LICENSES.txt`](legal/THIRD_PARTY_LICENSES.txt), not to the
project as a whole. Credits shows a short dependency list and opens the full
notices, license texts, and LGPL relinking information for each component.
The `.deb` contains one combined document at:

```text
/Applications/vless-core.app/THIRD_PARTY_LICENSES.txt
```

The project license is included separately at
`/Applications/vless-core.app/LICENSE` and does not replace any third-party
license.

Corresponding ZBar source is included in this repository. redsocks is shipped
as prebuilt ARMv7 and ARM64 executables under `third_party/` and is not rebuilt
as part of the application package.

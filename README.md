# vless-core-app

`vless-core-app` is an iOS 6–10 app + root daemon for full-device VLESS/SOCKS5 routing.

## Compatibility

- iOS 6.x through iOS 10.x
- All compatible 32-bit devices
- ARMv7 only; 64-bit ARM devices are not supported
- Jailbreak required

The app, daemon, bundled core, and helper binaries are all built for ARMv7 with iOS 6.0 as the minimum deployment target.

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
- `../vless-core-cli/third_party/curl-ios6-armv7/bin/curl`
- `../vless-core-cli/third_party/cacert.pem`

Build them in `vless-core-cli`:

```bash
# build vless-core-cli assets first
cd /path/to/vless-core-cli
IOS_TOOLCHAIN=/path/to/ios6/toolchain
make openssl-ios6 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make curl-ios6 IOS_TOOLCHAIN=$IOS_TOOLCHAIN
make third_party/cacert.pem
make ios IOS_TOOLCHAIN=$IOS_TOOLCHAIN

# then build app package
cd /path/to/vless-core-app
make clean
make deb IOS_TOOLCHAIN=$IOS_TOOLCHAIN
```

Output:

- `build/com.vlesscore.app_iphoneos-arm.deb`
By default, package build takes binaries from sibling repo:

- `../vless-core-cli/vless-core-darwin-armv7`
- `../vless-core-cli/third_party/curl-ios6-armv7/bin/curl`
- `../vless-core-cli/third_party/cacert.pem`

Override paths if needed:

```bash
make deb \
  VLESS_CORE_BIN=/abs/path/to/vless-core-darwin-armv7 \
  VLESS_CORE_CURL_BIN=/abs/path/to/curl \
  CA_BUNDLE=/abs/path/to/cacert.pem
```

Package uses `gzip` compression for old iOS 6 `dpkg` compatibility.

## Runtime paths

- App: `/Applications/vless-core.app`
- Daemon API: `127.0.0.1:9093`
- Core binary: `/usr/bin/vless-core-darwin-armv7`
- Subscription fetch binary: `/usr/bin/vless-core-curl`
- CA bundle: `/usr/share/vless-core/cacert.pem`
- Redsocks helper: `/usr/bin/redsocks-vless-core`
- Logs:
  - `/var/log/vpnctld.log`
  - `/var/log/vless-core.log`

## Full-device backend

The daemon uses `pf + redsocks`.

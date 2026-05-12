# vless-core-app

`vless-core-app` is an iOS 6.x app + root daemon for full-device VLESS routing.

**Jailbreak required**

## Tested Device/OS

### Tested by Me

| Device | OS | Status |
| --- | --- | --- |
| iPhone 4s | iOS 6.1.3 | Works fine |
| iPad 4 | iOS 10.3.3 | Works fine |

### Tested by Others

| Device | OS | Status |
| --- | --- | --- |
| iPad 2 | iOS 6.1.3 | Works fine |
| iPhone 5 | iOS 8.4.1 | Works, but has UI bugs |
| iPhone 5 | iOS 10.3.3 | Not working: after install, SpringBoard crashes into Safe Mode |
| iPad 2 | iOS 9.3.5 | Not working: no response from daemon |

see [Issues](https://github.com/notfence/vless-core-app/issues) page for current bug list

**<u>Compatibility with other iOS versions/devices is not guaranteed!</u>**

## Install on iOS

### Install from latest release (.deb)

1. Download `.deb` from [latest release](https://github.com/notfence/vless-core-app/releases/latest).
2. Put the `.deb` file on your device (for example: `/var/mobile/`).
3. In iFile, find the `.deb`, tap it, and press `Install`.
4. Device should respring.

Also you can use terminal app to install it: 
`dpkg -i com.vlesscore.app_iphoneos-arm.deb`

### Install your own build via SSH (scp + dpkg)


```bash
# on build machine
scp build/com.vlesscore.app_iphoneos-arm.deb root@<idevice-ip>:/var/root/

# on iDevice
dpkg -i com.vlesscore.app_iphoneos-arm.deb
```

## Supported Protocols

Bundled core supports:

- `VLESS + TCP + Reality + xtls-rprx-vision`
- `VLESS + TLS + XHTTP (mode=packet-up)`

Protocol semantics are aligned with `xray-core` for the supported transports and URI parameters.

## Build

Need `vless-core-cli` first.

Build or download it from:

- Repo: https://github.com/notfence/vless-core-cli
- Latest release: https://github.com/notfence/vless-core-cli/releases/latest

`vless-core-app` package build expects these files:

- `../vless-core-cli/vless-core-darwin-amrv7`
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

- `../vless-core-cli/vless-core-darwin-amrv7`
- `../vless-core-cli/third_party/curl-ios6-armv7/bin/curl`
- `../vless-core-cli/third_party/cacert.pem`

Override paths if needed:

```bash
make deb \
  VLESS_CORE_BIN=/abs/path/to/vless-core-darwin-amrv7 \
  VLESS_CORE_CURL_BIN=/abs/path/to/curl \
  CA_BUNDLE=/abs/path/to/cacert.pem
```

Package uses `gzip` compression for old iOS 6 `dpkg` compatibility.

## Runtime paths

- App: `/Applications/vless-core.app`
- Daemon API: `127.0.0.1:9093`
- Core binary: `/usr/bin/vless-core-darwin-amrv7`
- Subscription fetch binary: `/usr/bin/vless-core-curl`
- CA bundle: `/usr/share/vless-core/cacert.pem`
- Redsocks helper: `/usr/bin/redsocks-vless-core`
- Logs:
  - `/var/log/vpnctld.log`
  - `/var/log/vless-core.log`

## Full-device backend selection

The daemon chooses the first usable backend in order:

1. `ipfw + redsocks`
2. `pf + redsocks`

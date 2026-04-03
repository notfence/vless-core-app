# vless-core-app

`vless-core-app` is an iOS 6.x app + root daemon for full-device VLESS Reality routing.

**Jailbreak required**

## Tested Device/OS

Tested on **iPhone 4s**, **iPad 2** running **iOS 6.1.3**.
Compatibility with other iOS versions/devices is not guaranteed.

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
scp build/com.vlesscore.app_iphoneos-arm.deb root@<iphone-ip>:/var/root/

# on iPhone
dpkg -i com.vlesscore.app_iphoneos-arm.deb
```

## Supported Protocols

Bundled core supports:

- `VLESS + TCP + Reality + xtls-rprx-vision`
- `VLESS + TLS + XHTTP (mode=packet-up)`

Protocol semantics are aligned with `xray-core` for the supported transports and URI parameters.

## Build

Need `vless-core-cli` first (from sibling repo or release assets).

Download it from:

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

For a fresh clone, ensure packaging placeholders exist (empty dirs are not tracked by git):

```bash
mkdir -p packaging/Applications/vless-core.app packaging/usr/bin
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

1. `tun2socks` (`/dev/tun0` required)
2. `ipfw + redsocks`
3. `pf + redsocks`

So TCP full-device proxy mode can work even when `/dev/tun0` is missing.

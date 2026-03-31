# vless-core app (jailbreak)

`vless-core` is an iOS 6.1.3 jailbreak app + root daemon for full-device VLESS Reality routing.

## Tested Device/OS

Tested only on **iOS 6.1.3** on **iPhone 4s**.
Compatibility with other iOS versions/devices is not guaranteed.

## Build

```bash
# build core binary first
cd /path/to/vless-core-cli
make ios

# then build app package
cd /path/to/vless-core-app
make clean
make deb
```

Output:

- `build/com.vlesscore.app_iphoneos-arm.deb`
By default, package build takes core binary from sibling repo:

- `../vless-core-cli/vless-core-darwin-amrv7`

Override path if needed:

```bash
make deb VLESS_CORE_BIN=/abs/path/to/vless-core-darwin-amrv7
```

Package uses `gzip` compression for old iOS 6 `dpkg` compatibility.

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

## Runtime paths

- App: `/Applications/vless-core.app`
- Daemon API: `127.0.0.1:9093`
- Core binary: `/usr/bin/vless-core-darwin-amrv7`
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

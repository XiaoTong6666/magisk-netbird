# Magisk NetBird

![Release](https://img.shields.io/github/v/release/ahsaboy/magisk-netbird)
![CI](https://img.shields.io/github/actions/workflow/status/ahsaboy/magisk-netbird/release.yml?branch=main&label=CI)
![Downloads](https://img.shields.io/github/downloads/ahsaboy/magisk-netbird/total)
![NetBird](https://img.shields.io/github/v/release/netbirdio/netbird?label=NetBird)
![Magisk](https://img.shields.io/badge/Magisk-%E2%89%A520.4-green)
![Arch](https://img.shields.io/badge/arch-arm64%20%7C%20armv7%20%7C%20x86__64-lightgrey)

**[English](README.md) · [中文](README.zh-CN.md)**

Minimal Magisk module wrapper for the NetBird CLI daemon. Official NetBird
binaries (currently v0.79.0) are bundled for three architectures and packaged
by GitHub Actions.

DNS management is disabled by default when joining with `netbird.service up`.

## Download

| Zip | Devices |
| --- | --- |
| `magisk-netbird-arm64-v8a.zip` | arm64-v8a (most modern phones) |
| `magisk-netbird-armv7.zip` | 32-bit ARM (armeabi-v7a) |
| `magisk-netbird-x86_64.zip` | x86_64 (emulators, some Chromebooks) |

Latest release: <https://github.com/ahsaboy/magisk-netbird/releases/latest>

Every install stamps a per-architecture `updateJson` into `module.prop`
(`update/update-<arch>.json`), so the Magisk app shows an
**update available** banner after a new release. The banner works in
Kitsune and older managers too; the ACTION button needs Magisk v28+.

## Cutting a release

```sh
# bump version + versionCode in module.prop (v1.3.0 -> 10300), commit, then:
git tag v1.3.0
git push origin main v1.3.0
```

The `Release` workflow downloads the matching official NetBird release for
each architecture, verifies sha256 against `checksums.txt`, packages the three
zips, attaches them to the GitHub Release, and refreshes `update/*.json`,
`update.json` and `CHANGELOG.md` on `main`.

Local packaging without CI (needs `netbird/bin/netbird-<arch>` in place,
otherwise the installer falls back to downloading at install time):

```sh
zip -r9 magisk-netbird-local.zip META-INF customize.sh module.prop service.sh \
  uninstall.sh action.sh README.md netbird system
```

## Usage

Before reboot:

```sh
su -c '/dev/netbird.service up --setup-key <KEY> --management-url <URL>'
su -c '/dev/netbird.service status'
```

After reboot:

```sh
su -c 'netbird.service up --setup-key <KEY> --management-url <URL>'
su -c 'netbird.service status'
su -c 'netbird.service log'
```

To keep the setup key out of shell history and `ps` output, prefer a file:

```sh
su -c 'echo -n <KEY> > /data/adb/netbird/setup.key && chmod 600 /data/adb/netbird/setup.key'
su -c 'netbird.service up --setup-key-file /data/adb/netbird/setup.key --management-url <URL>'
```

In the Magisk app (v28+), the module's **ACTION** button runs `action.sh`: it
refreshes CA bundle, route rules and firewall rules, then prints status.

## Configuration

Defaults are set in `netbird/settings.sh`; override any of them via environment
variables (environment outranks CLI flags in NetBird):

| Variable | Default | Effect |
| --- | --- | --- |
| `NB_DISABLE_DNS` | `true` | Also enforced on `up` via `--disable-dns`. |
| `NB_DISABLE_IPV6` | `false` | When `true`, `up` appends `--disable-ipv6` (silences `ip6tables nat` warnings on Android). |
| `NB_DISABLE_FIREWALL` | `false` | When `true`, `up` appends `--disable-firewall` (client stops managing firewall rules). |
| `NB_DISABLE_SSH_CONFIG` | `true` | Skips writing `/etc/ssh/ssh_config.d` (read-only on Android). |
| `NB_SKIP_NFTABLES_CHECK` | `true` | Skips the nftables probe, which always fails on Android. |
| `NB_SKIP_DNS_PROBE` | `true` | Skips the local-resolver startup probe. |
| `NB_NETWORK_MONITOR` | `true` | Upstream defaults to `false` on Linux; enabled for faster reconnects after network switches. |
| `NB_STATE_DIR` | `/data/adb/netbird` | Writable location for `state.json` / WireGuard keys (upstream default `/var/lib/netbird` does not exist on Android). |
| `NB_LOG_LEVEL` | `info` | NetBird log level. |

Flags added by `up` persist in `config.json` and are applied on (re)connect,
so after changing them run `netbird.service down` followed by
`netbird.service up` (or `netbird.service restart`).

The status watcher re-applies the Android root route rule every refresh cycle
(default 60s), so Wi-Fi/cellular switches no longer require a manual restart.
`netbird.service stop` (and uninstall) removes all ip rules and iptables rules
the module added.

## Dynamic status

While the daemon is running, `module.prop` is refreshed periodically. Because module descriptions are single-line metadata, status is shown as compact paired fields such as IP/peers, management/signal, relay/interface, memory, CA count, and refresh time.

## Custom CA trust

For self-hosted NetBird servers with a private CA, place PEM certificates in `/data/adb/netbird/certs/` as `.crt`, `.pem`, or `.cer` files. `/data/adb/netbird/ca.crt` is also loaded automatically. Restart NetBird after changing certificates:

```sh
su -c 'netbird.service restart'
su -c '/data/adb/netbird/scripts/cert-trust.sh status'
```

The module injects `/system/etc/resolv.conf` for the Linux binary runtime. Android's normal app DNS is not changed by this; `netbird.service up` still disables NetBird DNS management with `--disable-dns`.

Direct NetBird commands should include the module daemon address:

```sh
su -c 'netbird --daemon-addr unix:///data/adb/netbird/run/netbird.sock status'
```

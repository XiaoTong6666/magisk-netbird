# Magisk NetBird

Minimal Magisk module wrapper for the NetBird CLI daemon.

DNS management is disabled by default when joining with `netbird.service up`.

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

The module injects `/system/etc/resolv.conf` for the Linux binary runtime. Android's normal app DNS is not changed by this; `netbird.service up` still disables NetBird DNS management with `--disable-dns`.

Direct NetBird commands should include the module daemon address:

```sh
su -c 'netbird --daemon-addr unix:///data/adb/netbird/run/netbird.sock status'
```

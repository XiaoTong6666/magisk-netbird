#!/system/bin/sh

/data/adb/netbird/scripts/netbird.service stop >/dev/null 2>&1 || true
rm -rf /data/adb/netbird

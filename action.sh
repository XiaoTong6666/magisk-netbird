#!/system/bin/sh
# Executed when the user clicks the ACTION button in the Magisk app (v28+).
# Refreshes CA bundle, route rules and firewall rules, then shows status.

MODDIR=${0%/*}
export NB_MOD_DIR="$MODDIR"

SVC="/data/adb/netbird/scripts/netbird.service"
[ -x "$SVC" ] || SVC="$MODDIR/system/bin/netbird.service"

if [ ! -x "$SVC" ]; then
  echo "NetBird service script not found."
  exit 1
fi

"$SVC" refresh
"$SVC" status

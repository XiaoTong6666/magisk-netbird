#!/system/bin/sh
# NOTE: This file is sourced by other scripts; do NOT set -e here, or a
# failing command in a sourcing script (e.g. a non-zero `netbird up`) would
# abort the whole script before it can capture the return code.

NB_DIR="/data/adb/netbird"
NB_BIN_DIR="$NB_DIR/bin"
NB_SCRIPTS_DIR="$NB_DIR/scripts"
NB_RUN_DIR="$NB_DIR/run"
NB_CERT_DIR="$NB_DIR/certs"
NB_CONFIG_FILE="$NB_DIR/config.json"
NB_SOCKET="$NB_RUN_DIR/netbird.sock"
NB_LOG_FILE_PATH="$NB_RUN_DIR/client.log"
NB_SERVICE_LOG_FILE="$NB_RUN_DIR/service.log"
NB_CA_BUNDLE="$NB_RUN_DIR/ca-bundle.pem"
NB_CA_COUNT_FILE="$NB_RUN_DIR/ca-bundle.count"

# Persistent state (state.json, WireGuard keys) must live on a writable path;
# the upstream default (/var/lib/netbird) does not exist on Android.
NB_STATE_DIR="${NB_STATE_DIR:-$NB_DIR}"

if [ -z "${NB_MOD_DIR:-}" ] && [ -f "$NB_DIR/module.path" ]; then
  NB_MOD_DIR="$(cat "$NB_DIR/module.path" 2>/dev/null || true)"
fi

export PATH="$NB_BIN_DIR:$NB_SCRIPTS_DIR:/data/adb/magisk:/data/adb/ksu/bin:$PATH:/system/bin"
export HOME="$NB_DIR"
export USER="${USER:-root}"
export LOGNAME="${LOGNAME:-root}"
export SHELL="${SHELL:-/system/bin/sh}"
export NB_CONFIG="$NB_CONFIG_FILE"
export NB_DAEMON_ADDR="unix://$NB_SOCKET"
export NB_LOG_FILE="$NB_LOG_FILE_PATH"
export NB_LOG_LEVEL="${NB_LOG_LEVEL:-info}"
export NB_DISABLE_DNS="${NB_DISABLE_DNS:-true}"
# Official client environment variables (see docs.netbird.io/client/environment-variables):
# - NB_DISABLE_SSH_CONFIG: don't write /etc/ssh/ssh_config.d (read-only on Android).
# - NB_SKIP_NFTABLES_CHECK: skip the nftables probe that always fails on Android.
# - NB_SKIP_DNS_PROBE: skip the local-resolver startup probe (DNS mgmt is disabled).
# - NB_NETWORK_MONITOR: upstream defaults to false on Linux; we want network-switch handling.
export NB_DISABLE_SSH_CONFIG="${NB_DISABLE_SSH_CONFIG:-true}"
export NB_SKIP_NFTABLES_CHECK="${NB_SKIP_NFTABLES_CHECK:-true}"
export NB_SKIP_DNS_PROBE="${NB_SKIP_DNS_PROBE:-true}"
export NB_NETWORK_MONITOR="${NB_NETWORK_MONITOR:-true}"
export NB_STATE_DIR
export SSL_CERT_FILE="$NB_CA_BUNDLE"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/system/etc/security/cacerts:/apex/com.android.conscrypt/cacerts:/system/etc/security/cacerts_google}"

NB_DAEMON_CMD="netbird service run --config $NB_CONFIG_FILE --daemon-addr $NB_DAEMON_ADDR --log-file $NB_LOG_FILE_PATH"
export NB_DAEMON_CMD

# "up" flags handled by netbird.service. Deliberately NOT exported by default:
# environment variables outrank CLI flags in NetBird, so exporting a default
# "false" would break an explicit `--disable-ipv6` passed on the command line.
# Set them to "true" in the environment to opt in.
NB_DISABLE_IPV6="${NB_DISABLE_IPV6:-false}"
NB_DISABLE_FIREWALL="${NB_DISABLE_FIREWALL:-false}"

mkdir -p "$NB_RUN_DIR" "$NB_CERT_DIR"

CURRENT_TIME="$(date '+%H:%M:%S')"

log() {
  level="$1"
  shift
  # Rotate service.log at 1 MiB (client.log is rotated by NetBird itself).
  if [ -f "$NB_SERVICE_LOG_FILE" ]; then
    log_size="$(wc -c < "$NB_SERVICE_LOG_FILE" 2>/dev/null | tr -d ' ' || true)"
    case "$log_size" in
      ''|*[!0-9]*) log_size=0 ;;
    esac
    if [ "$log_size" -gt 1048576 ]; then
      mv -f "$NB_SERVICE_LOG_FILE" "$NB_SERVICE_LOG_FILE.bak" 2>/dev/null || true
    fi
  fi
  echo "$CURRENT_TIME [$level]: $*" >> "$NB_SERVICE_LOG_FILE"
  if [ -t 1 ]; then
    echo "$CURRENT_TIME [$level]: $*"
  fi
}

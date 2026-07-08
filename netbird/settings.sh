#!/system/bin/sh
set -e

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
export SSL_CERT_FILE="$NB_CA_BUNDLE"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/system/etc/security/cacerts:/apex/com.android.conscrypt/cacerts:/system/etc/security/cacerts_google}"

NB_DAEMON_CMD="netbird service run --config $NB_CONFIG_FILE --daemon-addr $NB_DAEMON_ADDR --log-file $NB_LOG_FILE_PATH"
export NB_DAEMON_CMD

mkdir -p "$NB_RUN_DIR" "$NB_CERT_DIR"

CURRENT_TIME="$(date '+%H:%M:%S')"

log() {
  level="$1"
  shift
  echo "$CURRENT_TIME [$level]: $*" >> "$NB_SERVICE_LOG_FILE"
  if [ -t 1 ]; then
    echo "$CURRENT_TIME [$level]: $*"
  fi
}

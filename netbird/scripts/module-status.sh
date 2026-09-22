#!/system/bin/sh

DIR=$(dirname "$(realpath "$0")")
. "$DIR/../settings.sh"

prop_update_interval="${NB_PROP_UPDATE_INTERVAL:-60}"
watch_pid_file="$NB_RUN_DIR/module-status.pid"
default_description="NetBird CLI daemon for Magisk with DNS management disabled by default."

# Print every existing module.prop that should receive the status line: the
# active module dir, the staged upgrade dir, and the module.path hint. After
# an install, module.path points at modules_update while the Magisk app still
# shows the active dir, so updating only one of them leaves a stale view.
module_prop_paths() {
  for path in \
    "${NB_MOD_DIR:-}/module.prop" \
    "$(cat "$NB_DIR/module.path" 2>/dev/null || true)/module.prop" \
    /data/adb/modules/magisk-netbird/module.prop \
    /data/adb/modules_update/magisk-netbird/module.prop; do
    [ -n "$path" ] && [ "$path" != "/module.prop" ] && [ -f "$path" ] && echo "$path"
  done | sort -u
}

daemon_pid() {
  if command -v busybox >/dev/null 2>&1; then
    busybox pgrep -f "$NB_DAEMON_CMD" 2>/dev/null | head -n 1
    return 0
  fi
  ps -A -o PID,ARGS 2>/dev/null |
    awk '/netbird service run/ && $0 !~ /awk/ { print $1; exit }'
}

daemon_running() {
  pid="$(daemon_pid)"
  [ -n "$pid" ] && [ -r "/proc/$pid/status" ]
}

status_field() {
  key="$1"
  awk -F': ' -v key="$key" '$1 == key { print $2; exit }'
}

clean_value() {
  tr '\r\n' '  ' |
    sed 's/[[:cntrl:]]//g; s/  */ /g; s/^ *//; s/ *$//'
}

memory_usage() {
  pid="$(daemon_pid)"
  [ -n "$pid" ] || return 1
  rss_kb="$(awk '/^VmRSS:/ { print $2; exit }' "/proc/$pid/status" 2>/dev/null)"
  [ -n "$rss_kb" ] || return 1
  awk -v kb="$rss_kb" 'BEGIN {
    if (kb >= 1048576) {
      printf "%.1fG", kb / 1048576
    } else if (kb >= 1024) {
      printf "%.1fM", kb / 1024
    } else {
      printf "%dK", kb
    }
  }'
}

ca_count() {
  count="$(cat "$NB_CA_COUNT_FILE" 2>/dev/null || true)"
  case "$count" in
    ''|*[!0-9]*)
      echo 0
      ;;
    *)
      echo "$count"
      ;;
  esac
}

short_peers() {
  peers="$1"
  echo "$peers" | awk '{
    if ($2 == "Connected" || $3 == "Connected") {
      print $1
    } else {
      print $0
    }
  }'
}

short_available() {
  value="$1"
  echo "$value" | awk '{
    if ($2 == "Available" || $3 == "Available") {
      print $1
    } else {
      print $0
    }
  }'
}

build_description() {
  now="$(date '+%H:%M:%S' 2>/dev/null || echo unknown)"
  mem="$(memory_usage 2>/dev/null || true)"
  cas="$(ca_count)"
  [ -n "$mem" ] || mem="N/A"

  if ! daemon_running; then
    echo "NB=stopped | Mem=$mem  CA=$cas | Upd=$now"
    return 0
  fi

  status_text="$(netbird --daemon-addr "$NB_DAEMON_ADDR" status 2>/dev/null || true)"
  if [ -z "$status_text" ]; then
    echo "NB=running | Status=unavailable  Mem=$mem | CA=$cas  Upd=$now"
    return 0
  fi

  fqdn="$(printf '%s\n' "$status_text" | status_field "FQDN" | clean_value)"
  ip="$(printf '%s\n' "$status_text" | status_field "NetBird IP" | clean_value)"
  ipv6="$(printf '%s\n' "$status_text" | status_field "NetBird IPv6" | clean_value)"
  peers="$(printf '%s\n' "$status_text" | status_field "Peers count" | clean_value)"
  peers="$(short_peers "$peers" | clean_value)"
  management="$(printf '%s\n' "$status_text" | status_field "Management" | clean_value)"
  signal="$(printf '%s\n' "$status_text" | status_field "Signal" | clean_value)"
  relays="$(printf '%s\n' "$status_text" | status_field "Relays" | clean_value)"
  relays="$(short_available "$relays" | clean_value)"
  iface="$(printf '%s\n' "$status_text" | status_field "Interface type" | clean_value)"
  port="$(printf '%s\n' "$status_text" | status_field "Wireguard port" | clean_value)"

  summary="NB=running"
  [ -n "$fqdn" ] && summary="$summary | Host=$fqdn"
  if [ -n "$ip" ]; then
    summary="$summary  IP=$ip"
  elif [ -n "$ipv6" ]; then
    summary="$summary  IPv6=$ipv6"
  fi
  [ -n "$peers" ] && summary="$summary | Peers=$peers"
  summary="$summary  Mem=$mem"
  [ -n "$management" ] && summary="$summary | Mgmt=$management"
  [ -n "$signal" ] && summary="$summary  Sig=$signal"
  [ -n "$relays" ] && summary="$summary | Relay=$relays"
  if [ -n "$iface" ] && [ -n "$port" ]; then
    summary="$summary  IF=$iface:$port"
  elif [ -n "$iface" ]; then
    summary="$summary  IF=$iface"
  fi
  summary="$summary | CA=$cas  Upd=$now"

  printf '%s\n' "$summary" | clean_value
}

write_module_prop() {
  prop_files="$(module_prop_paths)"
  [ -n "$prop_files" ] || return 0
  description="$(build_description)"
  [ -n "$description" ] || description="$default_description"

  for prop_file in $prop_files; do
    tmp_file="$prop_file.tmp.$$"
    awk -v description="$description" '
      BEGIN { updated = 0 }
      /^description=/ {
        print "description=" description
        updated = 1
        next
      }
      { print }
      END {
        if (!updated) {
          print "description=" description
        }
      }
    ' "$prop_file" > "$tmp_file" &&
      mv -f "$tmp_file" "$prop_file" &&
      chmod 0644 "$prop_file" 2>/dev/null || {
        rm -f "$tmp_file"
        return 1
      }
  done
}

watcher_running() {
  [ -f "$watch_pid_file" ] || return 1
  pid="$(cat "$watch_pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

start_watcher() {
  if watcher_running; then
    return 0
  fi
  nohup "$0" watch </dev/null >/dev/null 2>&1 &
  echo "$!" > "$watch_pid_file"
}

stop_watcher() {
  if watcher_running; then
    pid="$(cat "$watch_pid_file" 2>/dev/null || true)"
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$watch_pid_file"
}

case "${1:-update}" in
  update)
    write_module_prop
    ;;
  start)
    start_watcher
    ;;
  watch)
    while true; do
      # Re-check the Android route rule regularly so a Wi-Fi/cellular switch
      # does not leave the daemon with a stale routing table lookup.
      if [ -x "$NB_SCRIPTS_DIR/netbird.service" ]; then
        "$NB_SCRIPTS_DIR/netbird.service" route >/dev/null 2>&1 || true
      fi
      write_module_prop >/dev/null 2>&1 || true
      sleep "$prop_update_interval"
    done
    ;;
  stop)
    stop_watcher
    write_module_prop
    ;;
  *)
    echo "usage: module-status.sh {update|start|stop|watch}"
    exit 1
    ;;
esac

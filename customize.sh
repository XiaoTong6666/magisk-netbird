#!/system/bin/sh

SKIPUNZIP=1
SKIPMOUNT=false

if [ "$BOOTMODE" != true ]; then
  ui_print "! Please install in Magisk Manager or KernelSU/APatch Manager"
  abort "! Install from recovery is not supported"
fi

NB_DIR="/data/adb/netbird"
NB_BIN_DIR="$NB_DIR/bin"
NB_SCRIPTS_DIR="$NB_DIR/scripts"
NB_RUN_DIR="$NB_DIR/run"

case "$ARCH" in
  arm64)
    RELEASE_ARCH="arm64"
    BUNDLED_ARCH="arm64"
    ;;
  arm)
    RELEASE_ARCH="armv6"
    BUNDLED_ARCH="arm"
    ;;
  *)
    abort "! Unsupported architecture: $ARCH"
    ;;
esac

ui_print "- Detected architecture: $ARCH"

gh_download() {
  repo="$1"
  match="$2"
  download_url="$(
    wget --no-check-certificate --timeout=10 -qO- "https://api.github.com/repos/${repo}/releases/latest" |
      grep "browser_download_url" |
      grep "$match" |
      sed 's/.*"browser_download_url": "\([^"]*\)".*/\1/' |
      head -n 1 || true
  )"
  if [ -z "$download_url" ]; then
    return 1
  fi
  filename=$(basename "$download_url")
  ui_print "- Downloading $filename"
  wget --no-check-certificate --timeout=120 -qO "$TMPDIR/$filename" "$download_url" || return 1
}

ui_print "- Extracting module files"
unzip -qqo "$ZIPFILE" -x 'META-INF/*' 'netbird/*' -d "$MODPATH"

mkdir -p "$NB_BIN_DIR" "$NB_SCRIPTS_DIR" "$NB_RUN_DIR" "$MODPATH/system/bin"
echo "$MODPATH" > "$NB_DIR/module.path"

unzip -qqjo "$ZIPFILE" "netbird/scripts/*" -d "$NB_SCRIPTS_DIR"
unzip -qqjo "$ZIPFILE" "netbird/settings.sh" -d "$NB_DIR"

unzip -qqjo "$ZIPFILE" "netbird/bin/netbird-$BUNDLED_ARCH" -d "$NB_BIN_DIR" 2>/dev/null || true
if [ -f "$NB_BIN_DIR/netbird-$BUNDLED_ARCH" ]; then
  mv -f "$NB_BIN_DIR/netbird-$BUNDLED_ARCH" "$NB_BIN_DIR/netbird"
fi
if [ ! -f "$NB_BIN_DIR/netbird" ]; then
  unzip -qqjo "$ZIPFILE" "netbird/bin/netbird" -d "$NB_BIN_DIR" 2>/dev/null || true
fi

if [ ! -f "$NB_BIN_DIR/netbird" ]; then
  gh_download "netbirdio/netbird" "netbird_.*_linux_${RELEASE_ARCH}\\.tar\\.gz" || abort "! Unable to download NetBird release"
  tar -xzf "$TMPDIR/$filename" -C "$TMPDIR" || abort "! Unable to extract NetBird archive"
  found="$(find "$TMPDIR" -type f -name netbird | head -n 1)"
  [ -n "$found" ] || abort "! NetBird binary not found in archive"
  mv -f "$found" "$NB_BIN_DIR/netbird"
fi

ln -sf "$NB_BIN_DIR/netbird" "$MODPATH/system/bin/netbird"
ln -sf "$NB_SCRIPTS_DIR/netbird.service" "$MODPATH/system/bin/netbird.service"

ui_print "- Setting permissions"
set_perm_recursive "$NB_BIN_DIR" 0 0 0755 0755 "u:object_r:system_file:s0"
set_perm_recursive "$NB_SCRIPTS_DIR" 0 0 0755 0755 "u:object_r:system_file:s0"
set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755 "u:object_r:system_file:s0"
set_perm "$MODPATH/service.sh" 0 0 0755 "u:object_r:system_file:s0"

ui_print "- Starting NetBird service in background"
"$NB_SCRIPTS_DIR/start.sh" postinstall >/dev/null 2>&1 &

ln -sf "$NB_BIN_DIR/netbird" /dev/netbird
ln -sf "$NB_SCRIPTS_DIR/netbird.service" /dev/netbird.service

ui_print "-----------------------------------------------------------"
ui_print " NetBird commands"
ui_print "-----------------------------------------------------------"
ui_print " Before reboot:"
ui_print "   su -c '/dev/netbird.service up --setup-key <KEY> --management-url <URL>'"
ui_print "   su -c '/dev/netbird.service status'"
ui_print " After reboot:"
ui_print "   su -c 'netbird.service up --setup-key <KEY> --management-url <URL>'"
ui_print "   su -c 'netbird.service status'"
ui_print " DNS management is disabled by default with --disable-dns."

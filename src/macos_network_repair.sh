#!/bin/bash
set -u

DO_REPAIR=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
NETWORK_SERVICE=""
RESET_DNS=false
RENEW_DHCP=false
CYCLE_WIFI=false
VPN_SERVICE=""
VPN_ACTION=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: macos_network_repair.sh [options]

  --repair                  Flush DNS caches and restart name-resolution services.
  --service NAME            Network service used by DHCP or DNS actions.
  --renew-dhcp              Renew DHCP for --service.
  --reset-dns               Return --service DNS servers to automatic/DHCP values.
  --cycle-wifi              Turn Wi-Fi off and on.
  --vpn-start NAME          Start a configured VPN service.
  --vpn-stop NAME           Stop a configured VPN service.
  --dry-run                 Show commands without changing the Mac.
  --yes                     Skip confirmation prompts.
  --output DIR              Save logs and verification output in DIR.
  -h, --help                Show help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair) DO_REPAIR=true; shift ;;
    --service) NETWORK_SERVICE="${2:-}"; shift 2 ;;
    --renew-dhcp) RENEW_DHCP=true; DO_REPAIR=true; shift ;;
    --reset-dns) RESET_DNS=true; DO_REPAIR=true; shift ;;
    --cycle-wifi) CYCLE_WIFI=true; DO_REPAIR=true; shift ;;
    --vpn-start) VPN_ACTION="start"; VPN_SERVICE="${2:-}"; DO_REPAIR=true; shift 2 ;;
    --vpn-stop) VPN_ACTION="stop"; VPN_SERVICE="${2:-}"; DO_REPAIR=true; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 3; }
if { $RENEW_DHCP || $RESET_DNS; } && [ -z "$NETWORK_SERVICE" ]; then echo "--service is required for DHCP or DNS repair." >&2; exit 2; fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./macos-network-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_admin() {
  description="$1"; shift
  if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" /usr/bin/sudo "$@"; fi
}
get_wifi_device() {
  /usr/sbin/networksetup -listallhardwareports 2>/dev/null | awk '/Hardware Port: (Wi-Fi|AirPort)/ {getline; print $2; exit}'
}
service_exists() {
  /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | sed '1d' | grep -Fxq "$1"
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Host: $(hostname)"
    echo
    echo "Network services:"
    /usr/sbin/networksetup -listallnetworkservices 2>&1 || true
    echo
    echo "Interfaces and routes:"
    /sbin/ifconfig 2>&1 || true
    /usr/sbin/netstat -rn 2>&1 || true
    echo
    echo "DNS configuration:"
    /usr/sbin/scutil --dns 2>&1 | head -n 400 || true
    if [ -n "$NETWORK_SERVICE" ]; then
      echo
      echo "Service details for $NETWORK_SERVICE:"
      /usr/sbin/networksetup -getinfo "$NETWORK_SERVICE" 2>&1 || true
      /usr/sbin/networksetup -getdnsservers "$NETWORK_SERVICE" 2>&1 || true
    fi
    if [ -n "$VPN_SERVICE" ]; then
      echo
      echo "VPN state for $VPN_SERVICE:"
      /usr/sbin/scutil --nc status "$VPN_SERVICE" 2>&1 || true
    fi
    echo
    echo "Connectivity:"
    /sbin/ping -c 2 -W 2000 1.1.1.1 2>&1 || true
    /usr/bin/dig +time=3 +tries=1 apple.com 2>&1 | head -n 80 || true
  } > "$VERIFY" 2>&1
}

verify
if ! $DO_REPAIR; then log "Verification-only mode completed. Use repair options to apply changes."; exit 0; fi
if ! confirm "Apply the selected network repairs? Active network sessions may be interrupted."; then log "Repair cancelled by user."; exit 10; fi

run_admin "Flushing Directory Service caches" /usr/bin/dscacheutil -flushcache || true
run_admin "Restarting mDNSResponder" /usr/bin/killall -HUP mDNSResponder || true
if pgrep -x mDNSResponderHelper >/dev/null 2>&1; then run_admin "Restarting mDNSResponderHelper" /usr/bin/killall mDNSResponderHelper || true; fi

if $RENEW_DHCP; then
  if ! service_exists "$NETWORK_SERVICE"; then
    FAILURES=$((FAILURES + 1)); log "WARNING: Network service not found: $NETWORK_SERVICE"
  elif confirm "Renew DHCP configuration for $NETWORK_SERVICE?"; then
    run_admin "Renewing DHCP for $NETWORK_SERVICE" /usr/sbin/networksetup -setdhcp "$NETWORK_SERVICE" || true
  fi
fi

if $RESET_DNS; then
  if ! service_exists "$NETWORK_SERVICE"; then
    FAILURES=$((FAILURES + 1)); log "WARNING: Network service not found: $NETWORK_SERVICE"
  elif confirm "Reset DNS servers for $NETWORK_SERVICE to automatic values?"; then
    run_admin "Resetting DNS servers for $NETWORK_SERVICE" /usr/sbin/networksetup -setdnsservers "$NETWORK_SERVICE" Empty || true
  fi
fi

if $CYCLE_WIFI; then
  wifi_device=$(get_wifi_device)
  if [ -z "$wifi_device" ]; then
    FAILURES=$((FAILURES + 1)); log "WARNING: Wi-Fi interface not found."
  elif confirm "Cycle Wi-Fi on $wifi_device?"; then
    run_admin "Turning Wi-Fi off" /usr/sbin/networksetup -setairportpower "$wifi_device" off || true
    if ! $DRY_RUN; then sleep 3; fi
    run_admin "Turning Wi-Fi on" /usr/sbin/networksetup -setairportpower "$wifi_device" on || true
  fi
fi

if [ -n "$VPN_ACTION" ]; then
  if confirm "$VPN_ACTION configured VPN service $VPN_SERVICE?"; then
    run_action "Changing VPN state for $VPN_SERVICE" /usr/sbin/scutil --nc "$VPN_ACTION" "$VPN_SERVICE" || true
  fi
fi

if ! $DRY_RUN; then sleep 6; fi
verify
if [ "$FAILURES" -gt 0 ]; then log "Repair completed with $FAILURES warning(s)."; exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0

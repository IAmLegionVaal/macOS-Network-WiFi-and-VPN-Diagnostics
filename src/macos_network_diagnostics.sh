#!/bin/bash
set -u

TARGET="1.1.1.1"
DNS_NAME="example.com"
HOURS=24
OUTPUT_DIR=""

usage() { echo "Usage: macos_network_diagnostics.sh [--target IP_OR_HOST] [--dns-name NAME] [--hours N] [--output DIR]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-1.1.1.1}"; shift 2 ;;
    --dns-name) DNS_NAME="${2:-example.com}"; shift 2 ;;
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
case "$HOURS" in ''|*[!0-9]*) echo "--hours must be numeric" >&2; exit 2 ;; esac
[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./macos-network-diagnostics-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/network-report.txt"
CSV="$OUTPUT_DIR/interfaces.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"
echo 'interface,status,ipv4,ipv6,mac' > "$CSV"

section() { title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id'
section "Hardware ports" /usr/sbin/networksetup -listallhardwareports
section "Network services" /usr/sbin/networksetup -listallnetworkservices
section "Interfaces" /sbin/ifconfig -a
section "Routing table" /usr/sbin/netstat -rn
section "ARP and neighbours" /usr/sbin/arp -an
section "DNS configuration" /usr/sbin/scutil --dns
section "Proxy configuration" /usr/sbin/scutil --proxy
section "VPN and PPP state" /bin/bash -c 'scutil --nc list; echo; scutil --nc status "" 2>/dev/null || true'
section "DHCP leases" /bin/bash -c 'for i in $(ifconfig -l); do echo "--- $i"; ipconfig getpacket "$i" 2>/dev/null || true; done'
section "Wi-Fi state" /bin/bash -c 'airport_tool="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"; if [ -x "$airport_tool" ]; then "$airport_tool" -I; "$airport_tool" -s; else networksetup -getairportnetwork en0 2>/dev/null || true; fi'
section "Ping test" /sbin/ping -c 4 "$TARGET"
section "Route test" /sbin/route -n get "$TARGET"
section "DNS lookup" /usr/bin/dig "$DNS_NAME"
section "HTTPS test" /usr/bin/curl -I --connect-timeout 10 "https://$DNS_NAME"
section "Recent network events" /bin/bash -c "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(subsystem CONTAINS[c] \"network\") OR (process == \"configd\") OR (process CONTAINS[c] \"airport\") OR (eventMessage CONTAINS[c] \"DHCP\") OR (eventMessage CONTAINS[c] \"VPN\")' 2>/dev/null | tail -n 3000"

for iface in $(ifconfig -l); do
  status=$(ifconfig "$iface" 2>/dev/null | awk -F': ' '/status:/{print $2; exit}')
  ipv4=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
  ipv6=$(ifconfig "$iface" 2>/dev/null | awk '/inet6 / && $2 !~ /^fe80/ {print $2; exit}')
  mac=$(ifconfig "$iface" 2>/dev/null | awk '/ether / {print $2; exit}')
  printf '"%s","%s","%s","%s","%s"\n' "$iface" "${status:-unknown}" "$ipv4" "$ipv6" "$mac" >> "$CSV"
done

PING_OK=false
ping -c 1 -W 2000 "$TARGET" >/dev/null 2>&1 && PING_OK=true
DNS_OK=false
dig +short "$DNS_NAME" 2>/dev/null | grep -q . && DNS_OK=true
HTTPS_OK=false
curl -I --connect-timeout 10 "https://$DNS_NAME" >/dev/null 2>&1 && HTTPS_OK=true
DEFAULT_ROUTE=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')
OVERALL="Healthy"
if ! $PING_OK || ! $DNS_OK || ! $HTTPS_OK; then OVERALL="Attention required"; fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "target": "$TARGET",
  "dns_name": "$DNS_NAME",
  "default_gateway": "$DEFAULT_ROUTE",
  "ping_successful": $PING_OK,
  "dns_resolution_successful": $DNS_OK,
  "https_successful": $HTTPS_OK,
  "overall_status": "$OVERALL"
}
EOF
printf '\nmacOS network diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"

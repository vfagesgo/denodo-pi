#!/usr/bin/env bash
set -euo pipefail

# This script is meant to run once during boot from a systemd unit.
# It reads the cloud-init style boot network file, extracts the first Wi-Fi
# definition, and rewrites wpa_supplicant so the device joins that network.

LOG=/var/log/2-wifi_network_init.log
NETWORK_CONFIG_CANDIDATES=(
  "/boot/firmware/network-config"
  "/boot/network-config"
)
WPA_CONF=/etc/wpa_supplicant/wpa_supplicant.conf

log() {
  echo "[WIFI-INIT] $1" | tee -a "$LOG"
}

find_network_config() {
  local candidate
  for candidate in "${NETWORK_CONFIG_CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

extract_first_ssid() {
  awk '
    /access-points:/ { in_ap=1; next }
    in_ap && $0 ~ /^[[:space:]]*"/ {
      line=$0
      sub(/^[[:space:]]*"/, "", line)
      sub(/":[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$1"
}

extract_password_for_ssid() {
  awk -v target_ssid="$2" '
    $0 ~ /^[[:space:]]*"/ {
      current_ssid=$0
      sub(/^[[:space:]]*"/, "", current_ssid)
      sub(/":[[:space:]]*$/, "", current_ssid)
      next
    }
    current_ssid == target_ssid && $0 ~ /^[[:space:]]*password:[[:space:]]*"/ {
      password=$0
      sub(/^[[:space:]]*password:[[:space:]]*"/, "", password)
      sub(/"[[:space:]]*$/, "", password)
      print password
      exit
    }
  ' "$1"
}

extract_country() {
  awk '
    $0 ~ /^[[:space:]]*regulatory-domain:[[:space:]]*"/ {
      country=$0
      sub(/^[[:space:]]*regulatory-domain:[[:space:]]*"/, "", country)
      sub(/"[[:space:]]*$/, "", country)
      print country
      exit
    }
  ' "$1"
}

restart_wifi_stack() {
  if systemctl list-unit-files | grep -q '^NetworkManager\.service'; then
    systemctl restart NetworkManager || true
  fi

  if systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
    systemctl restart dhcpcd || true
  fi

  if systemctl list-unit-files | grep -q '^wpa_supplicant\.service'; then
    systemctl restart wpa_supplicant || true
  fi
}

main() {
  touch "$LOG"

  local network_config
  network_config=$(find_network_config || true)
  if [ -z "${network_config:-}" ]; then
    log "No boot network-config file found; nothing to apply"
    exit 0
  fi

  log "Using network config: $network_config"

  local ssid
  ssid=$(extract_first_ssid "$network_config")
  if [ -z "${ssid:-}" ]; then
    log "No Wi-Fi SSID found in $network_config"
    exit 0
  fi

  local password
  password=$(extract_password_for_ssid "$network_config" "$ssid")
  if [ -z "${password:-}" ]; then
    log "No password found for SSID '$ssid' in $network_config"
    exit 1
  fi

  local country
  country=$(extract_country "$network_config")
  country=${country:-FR}

  log "Applying Wi-Fi configuration for SSID '$ssid' with country '$country'"

  local tmp_conf
  tmp_conf=$(mktemp)

  # Generate the exact wpa_supplicant file we want on disk, then compare it to
  # the current one so the service can exit without restarting Wi-Fi on every
  # boot when nothing changed.
  cat > "$tmp_conf" <<EOF
country=$country
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$ssid"
    psk="$password"
}
EOF

  if [ -f "$WPA_CONF" ] && cmp -s "$tmp_conf" "$WPA_CONF"; then
    log "Wi-Fi configuration is already up to date"
    rm -f "$tmp_conf"
    exit 0
  fi

  if [ -f "$WPA_CONF" ]; then
    cp "$WPA_CONF" "${WPA_CONF}.bak"
    log "Backed up existing wpa_supplicant.conf to ${WPA_CONF}.bak"
  fi

  # Install the file with strict permissions because it contains the PSK.
  install -m 600 "$tmp_conf" "$WPA_CONF"
  rm -f "$tmp_conf"

  restart_wifi_stack
  log "Wi-Fi configuration applied successfully"
}

main "$@"

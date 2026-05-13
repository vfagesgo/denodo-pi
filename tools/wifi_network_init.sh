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
  local psk_line
  tmp_conf=$(mktemp)


  # Wait until the SSID becomes visible
  for i in {1..30}; do
      if nmcli -t -f SSID device wifi list | grep -Fxq "$ssid"; then
          echo "[WIFI-INIT] Found SSID '$ssid'"
          break
      fi

      echo "[WIFI-INIT] Waiting for SSID '$ssid'..."
      sleep 2
  done

  sudo nmcli device wifi connect "$ssid" password "$password"
  log "Wi-Fi configuration applied successfully"
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

# This script overwrite the applications config files
# by replacing them with the file provided under /boot/firmware/denodo folder

LOG=/var/log/0-Pre_boot_update.log
sudo touch $LOG

log_section() {
  echo "[SECTION $1] $2" | tee -a "$LOG"
}

log_step() {
  echo "[STEP] $1" | tee -a "$LOG"
}

main() {
  log_section "2" "Update config files"

  # Load environment variables from the boot partition when available.
  if [ -f /boot/firmware/denodo/denodo_config.env ]; then
      log_step "Loading config from /boot/firmware/denodo/denodo_config.env"
      set -o allexport
      source /boot/firmware/denodo/denodo_config.env
      set +o allexport
  else
      log_step "No config file found; continuing with defaults"
  fi

  if [ -f /boot/firmware/denodo/$DENODO_LIC ]; then
    log_step "Copy Denodo license $DENODO_LIC"
    sudo cp "/boot/firmware/denodo/$DENODO_LIC" "$DENODO_INSTALL/denodo-developer-lic-9.lic"
    sudo chown denodo:denodo "$DENODO_INSTALL/denodo-developer-lic-9.lic"
  fi

  
}

main "$@"

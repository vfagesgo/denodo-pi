#!/bin/bash
set -e

LOG=/var/log/3-denodo_init.log
echo "[INIT] Starting Denodo config..." | tee -a $LOG


# ---- 1. Load environment variables if present
if [ -f /boot/firmware/denodo/denodo_config.env ]; then
    echo "[INIT] Loading config from /boot/firmware/denodo/denodo_config.env" | tee -a $LOG
    set -o allexport
    source /boot/firmware/denodo/denodo_config.env
    set +o allexport
else
    echo "[INIT] No config file found" | tee -a $LOG
fi

# ---- 2. Wait for internet ----
#echo "[INIT] internet $SSID" | tee -a $LOG
#sudo chmod +x "/boot/firmware/denodo/tools/apply-wifi.sh"
#sudo -H "$/boot/firmware/denodo/tools/apply-wifi.sh"

echo "[INIT] Waiting for internet..." | tee -a $LOG

for i in {1..30}; do
  #VFG echo "--" | tee -a $LOG
  if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "[INIT] Internet OK" | tee -a $LOG
    ONLINE=1
    break
  fi
  sleep 2
done

# ---- 3. If no internet → stop here ----
if [ -z "$ONLINE" ]; then
  echo "[INIT] No internet. Skipping install phase." | tee -a $LOG
  exit 0
fi

# ---- 4. Online phase ----
echo "[INIT] Installing dependencies..." | tee -a $LOG
sudo apt update
sudo apt install git -y

# ---- 5. Install Denodo-Pi repository

# Defaults (in case .env is missing values)
GITHUB_REPO=${GITHUB_REPO:-""}
GITHUB_TOKEN=${GITHUB_TOKEN:-""}
INSTALL_DIR=${INSTALL_DIR:-"/opt/denodo-pi"}
BRANCH=${BRANCH:-"main"}

GITHUB_REPO_URL="https://x-access-token:${GITHUB_TOKEN}@github.com${GITHUB_REPO}"

echo "[INIT] Repo: $GITHUB_REPO" | tee -a $LOG
echo "[INIT] Install dir: $INSTALL_DIR" | tee -a $LOG
echo "[INIT] Branch: $BRANCH" | tee -a $LOG
mkdir -p "$INSTALL_DIR"

# Clone or update repo
if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "[INIT] Cloning Denodo-PI repository..." | tee -a $LOG
  git clone -b "$BRANCH" "$GITHUB_REPO_URL" "$INSTALL_DIR"
  chown -R denodo:denodo "$INSTALL_DIR"
  
else
  echo "[INIT] Updating repository..." | tee -a $LOG
  cd "$INSTALL_DIR"
  git pull
fi

# Example: run install script if exists
if [ -f "$INSTALL_DIR/install.sh" ]; then
  echo "[INIT] Running install.sh as Denodo" | tee -a $LOG
  chmod +x "$INSTALL_DIR/install.sh"
  sudo chmod +x "$INSTALL_DIR/tools/*.sh"
  sudo -H -u denodo bash "$INSTALL_DIR/install.sh"
fi

echo "[INIT] Completed" | tee -a $LOG
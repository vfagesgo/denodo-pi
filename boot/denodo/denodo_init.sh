#!/bin/bash
set +e

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

echo "[INIT] Waiting for network and GitHub access..." | tee -a $LOG

until getent hosts github.com >/dev/null 2>&1; do
    echo "[INIT] Waiting for DNS..." | tee -a $LOG
    sleep 5
done

until curl -s --head https://github.com >/dev/null 2>&1; do
    echo "[INIT] Waiting for HTTPS connectivity..." | tee -a $LOG
    sleep 5
done

echo "[INIT] Network is ready." | tee -a $LOG

# Wait for NTP clock synchronization
echo "[INIT] Waiting for clock synchronization..." | tee -a $LOG

if command -v timedatectl >/dev/null 2>&1; then
    timeout=120
    while [ $timeout -gt 0 ]; do
        if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then
            echo "[INIT] Clock synchronized." | tee -a $LOG
            break
        fi
        echo "[INIT] Waiting for NTP sync..." | tee -a $LOG
        sleep 5
        timeout=$((timeout-5))
    done
fi

echo "[INIT] Current time: $(date)"

# ---- 4. Online phase ----
echo "[INIT] Installing dependencies..." | tee -a $LOG
sudo apt update
sudo apt install git unzip -y

# ---- 5. Install Denodo-Pi repository

# Defaults (in case .env is missing values)
GITHUB_REPO=${GITHUB_REPO:-"vfagesgo/denodo-pi"}
GITHUB_TOKEN=${GITHUB_TOKEN:-""}
INSTALL_DIR="/opt/denodo-pi"
BRANCH=${BRANCH:-"main"}

GITHUB_REPO_URL="https://x-access-token:$GITHUB_TOKEN@github.com/$GITHUB_REPO.git"

echo "[INIT] Repo: $GITHUB_REPO" | tee -a $LOG
echo "[INIT] Install dir: $INSTALL_DIR" | tee -a $LOG
echo "[INIT] Branch: $BRANCH" | tee -a $LOG
mkdir -p "$INSTALL_DIR"

# Clone or update repo
if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "[INIT] Cloning Denodo-PI repository..." | tee -a $LOG
  echo "[INIT] GITHUB_TOKEN: $GITHUB_TOKEN" | tee -a $LOG
  echo "[INIT] GITHUB_REPO: $GITHUB_REPO" | tee -a $LOG
  echo "[INIT] GITHUB_REPO_URL: $GITHUB_REPO_URL" | tee -a $LOG
  git clone -b "$BRANCH" "$GITHUB_REPO_URL" "$INSTALL_DIR" | tee -a $LOG
  chown -R denodo:denodo "$INSTALL_DIR" | tee -a $LOG
  
else
  echo "[INIT] Updating repository (force reset)..." | tee -a "$LOG"
  cd "$INSTALL_DIR" || exit 1

  git fetch origin
  git reset --hard "origin/$BRANCH"
  git clean -fd
fi

# Example: run install script if exists
if [ -f "$INSTALL_DIR/install.sh" ]; then
  echo "[INIT] Running install.sh as Denodo" | tee -a $LOG
  chmod +x "$INSTALL_DIR/install.sh" 

  echo "[INIT] whoami=$(whoami)" | tee -a "$LOG"
  echo "[INIT] denodo user:" | tee -a "$LOG"
  id denodo >> "$LOG" 2>&1
  ls -l "$INSTALL_DIR/install.sh" >> "$LOG" 2>&1

  #sudo -H -u denodo bash "$INSTALL_DIR/install.sh" >> "$LOG" 2>&1
  runuser -l denodo -c "$INSTALL_DIR/install.sh" >> "$LOG" 2>&1
  rc=$?

  echo "[INIT] install.sh exit code=$rc" | tee -a "$LOG"

fi

echo "[INIT] Completed" | tee -a $LOG
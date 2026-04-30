#!/usr/bin/env bash
set -e

LOG=/var/log/4-denodo_install.log
sudo touch $LOG
sudo chown -R denodo:denodo "$LOG"
# This configures a bash environment with robust error handling and logging. Here's what each part does:
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

if [ 1 == 2 ]; then #VFG Debug
  echo "1️⃣ - Checking the input parameters and loading env variables" | tee -a $LOG

  # ---- 1. Load environment variables if present
  if [ -f /boot/firmware/denodo_config.env ]; then
      echo "[INSTAL] Loading config from /boot/firmware/denodo_config.env" | tee -a $LOG
      set -o allexport
      source /boot/firmware/denodo_config.env
      set +o allexport
  else
      echo "💩 - No config file found" | tee -a $LOG
  fi

  # Checking the hardware platform
  echo "2️⃣ - Verifying hardware compatibility" | tee -a $LOG
  if [[ -z "${test:-}" ]]; then
    model=$(grep "^Model" /proc/cpuinfo ; true)
    if [[  "$model" != *"Raspberry Pi Zero"* && "$model" != *"Raspberry Pi 4"* ]]; then
      # not a Pi Zero, Zero 2 or Pi 4
      echo "💩 - Installation only planned on Raspberry Pi Zero or Pi 4, will cowardly exit" | tee -a $LOG
      exit 1
    fi
  else
    echo "⚠️ ci-chroot-test is set → running in dev mode (non-Pi system)" | tee -a $LOG
  fi

  echo "3️⃣ - Checking User used for install" | tee -a $LOG
  user="${USER:-$(id -un 2>/dev/null || echo "#$(id -u)")}"
  if [ "$user" = "root" ] || [ "$user" = "#0" ]; then
    echo "💩 - Please run this script as a regular user with sudo privileges" | tee -a $LOG
    exit 1
  fi


  # Install Necessary Packages:
  echo "4️⃣ - Update the necessary packages" | tee -a $LOG
  sudo apt update -y 
  sudo apt upgrade -y 

  sudo apt install -y libglib2.0-dev python3-dev build-essential 

  # Install lates PGSql
  sudo apt install -y wget gnupg lsb-release 


  echo "5️⃣ - Install Postgres DB" | tee -a $LOG
  # Download PostgreSQL GPG key (new location!)
  wget -qO- https://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/postgresql.gpg > /dev/null

  # Add PostgreSQL repo (adapt codename: bullseye, bookworm, jammy, etc.)
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    | sudo tee /etc/apt/sources.list.d/pgdg.list

  echo "6️⃣ - Continue to install packages and updates"  | tee -a $LOG
  # Update and install
  sudo apt update
  sudo apt install -y postgresql-15 postgresql-client-15 libpq-dev

  sudo apt install libpq-dev -y
  sudo apt install nginx -y
  sudo apt install gettext -y
  sudo apt install git -y
  #VFG sudo apt install bluetooth pulseaudio pulseaudio-module-bluetooth python3-dbus -y
  sudo apt install python3-gi gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly -y
  sudo apt install python3-pil -y
  sudo apt install python3-pip -y
  sudo apt install dnsmasq network-manager -y

  echo "7️⃣ - Configure NAT routing for the captive portal" | tee -a $LOG
  # Pre-seed iptables-persistent answers
  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
  echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

  # Install packages non-interactively
  echo "8️⃣ - Install packages non-interactively" | tee -a $LOG
  sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables iptables-persistent

  sudo rm -f /var/lib/systemd/rfkill/*
  sudo systemctl restart systemd-rfkill.service

  # Configure the Postgres DB fro Denodo
  echo "1️⃣2️⃣ - Configure PostgreSQL database"

  pg_hba_files=(/etc/postgresql/*/main/pg_hba.conf)

  # Count existing trust entries (never fail under set -e)
  trust=$(sudo grep -cE '^local[[:space:]]+all[[:space:]]+all[[:space:]]+trust' "${pg_hba_files[@]}" || true)

  if [ "$trust" -lt 1 ]; then
    echo "Configuring PostgreSQL for trusted access" | tee -a $LOG

    sudo sed -i.orig -E \
      's/^(local[[:space:]]+all[[:space:]]+all[[:space:]]+)(peer|md5|scram-sha-256)$/\1trust/' \
      "${pg_hba_files[@]}"


    trust=$(sudo grep -cE '^local[[:space:]]+all[[:space:]]+all[[:space:]]+trust' "${pg_hba_files[@]}" || true)

    if [ "$trust" -lt 1 ]; then
      echo "Failed to configure PostgreSQL" | tee -a $LOG
      exit 1
    fi
  fi

  # ---- Remote access for denodo user (NEW) ----

  DENODO_SUBNET="192.168.0.0/16"
  DENODO_USER=${DENODO_PG_USER:-"denodo"}

  remote_denodopi=$(sudo grep -cE \
  "^host[[:space:]]+all[[:space:]]+$DENODO_USER[[:space:]]+$DENODO_SUBNET[[:space:]]+scram-sha-256" \
  "${pg_hba_files[@]}" || true)

  if [ "$remote_denodopi" -lt 1 ]; then
    echo "Configuring PostgreSQL network access for user '$DENODO_USER'" | tee -a $LOG

    sudo sed -i.orig -E \
      "/^#.*IPv4 local connections:/a host all $DENODO_USER $DENODO_SUBNET scram-sha-256" \
      "${pg_hba_files[@]}"
  fi

  echo "- Configure PostgreSQL listen_addresses" | tee -a $LOG

  pg_conf_files=(/etc/postgresql/*/main/postgresql.conf)

  for PG_CONF in "${pg_conf_files[@]}"; do
    echo "Configuring $PG_CONF" | tee -a $LOG

    # Ensure file exists
    if [ ! -f "$PG_CONF" ]; then
      echo "Config not found: $PG_CONF" | tee -a $LOG
      exit 1
    fi

    # Backup once
    if [ ! -f "$PG_CONF.orig" ]; then
      sudo cp "$PG_CONF" "$PG_CONF.orig"
    fi

    # Set listen_addresses = '*'
    sudo sed -i -E \
      "s|^[[:space:]]*#?[[:space:]]*listen_addresses[[:space:]]*=.*|listen_addresses = '*'|" \
      "$PG_CONF"

    # Verify
    if ! grep -q "^listen_addresses = '\\*'" "$PG_CONF"; then
      echo "Failed to update listen_addresses in $PG_CONF" | tee -a $LOG
      exit 1
    fi
  done


  for conf in "${pg_hba_files[@]}"; do
    version=$(echo "$conf" | cut -d/ -f4)
    name=$(echo "$conf" | cut -d/ -f5)

    sudo pg_ctlcluster "$version" "$name" restart 
  done

  if [[ -z "${test:-}" ]]; then
    sudo systemctl restart postgresql
  fi


  echo "- Configure PostgreSQL listen_addresses" | tee -a $LOG

  PG_CONF="/etc/postgresql/*/main/postgresql.conf"

  # Ensure config file exists
  if [ ! -f "$PG_CONF" ]; then
    echo "PostgreSQL config not found: $PG_CONF" | tee -a $LOG
    exit 1
  fi

  # Backup once (idempotent)
  if [ ! -f "$PG_CONF.orig" ]; then
    sudo cp "$PG_CONF" "$PG_CONF.orig"
  fi

  # Set listen_addresses to '*'
  sudo sed -i -E \
    "s|^[[:space:]]*#?[[:space:]]*listen_addresses[[:space:]]*=.*|listen_addresses = '*'|" \
    "$PG_CONF"

  # Verify change
  if ! grep -q "^listen_addresses = '\\*'" "$PG_CONF"; then
    echo "Failed to set listen_addresses" | tee -a $LOG
    exit 1
  fi


  # Postgres DB Config
  echo "1️⃣3️⃣ - Create Denodo Database" | tee -a $LOG
  DENODO_PG_USER=${DENODO_PG_USER:-"denodo"}
  DENODO_PG_PWD=${DENODO_PG_PWD:-"password"}

  role_exists=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='$DENODO_PG_USER'")

  if [ -z "$role_exists" ]; then
    echo "Creating PostgreSQL $DENODO_PG_USER User" | tee -a $LOG
    sudo -u postgres psql -c "CREATE USER $DENODO_PG_USER PASSWORD '$DENODO_PG_PWD'"
  else
    echo "Updating PostgreSQL $DENODO_PG_USER User" | tee -a $LOG
    sudo -u postgres psql -c "ALTER USER $DENODO_PG_USER WITH PASSWORD '$DENODO_PG_PWD';"
  fi

  db_exists=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='denodo'")

  if [ -z "$db_exists" ]; then
    echo "Creating PostgreSQL denodo DB" | tee -a $LOG
    sudo -u postgres psql -c \
      "CREATE DATABASE denodo OWNER=$DENODO_PG_USER LC_COLLATE='C' LC_CTYPE='C' ENCODING='UTF8' TEMPLATE template0"
  fi

  sudo -u postgres psql -c "ALTER ROLE $DENODO_PG_USER CREATEDB"
else 
#VFG Debug
  echo "1️⃣1️⃣ - Configure Python virtual environlent" | tee -a $LOG
  cd ~

  # Try to find any python3 version
  py_cmd=$(command -v python3 || true)
  if [ -z "$py_cmd" ]; then
      echo "💩 - Python 3 is not installed" | tee -a $LOG
      exit 1
  fi
  # Get the version number
  py_ver_str=$($py_cmd -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')

  # Extract major and minor
  py_major=$(echo "$py_ver_str" | cut -d. -f1)
  py_minor=$(echo "$py_ver_str" | cut -d. -f2)
  py_ver=$py_major.$py_minor

  # Check if version >= 3.10
  if [ "$py_major" -lt 3 ] || { [ "$py_major" -eq 3 ] && [ "$py_minor" -lt 10 ]; }; then
      echo "💩 - Please install Python 3.10 or higher (you have $py_ver_str)" | tee -a $LOG
      exit 1
  fi

  echo "✅ Python version $py_ver is OK" | tee -a $LOG
  python="$py_cmd"
  # ---- Virtual environment name ----
  VENV_DIR="venv_denodo"
  venv_cfg="$VENV_DIR/pyvenv.cfg"

  if [[ -f "${venv_cfg}" && "$(grep -c version\ =\ ${py_ver} ${venv_cfg})" -eq 0 ]]; then
    echo "💩 - Installed virtual env does not match needed version: remove it" | tee -a $LOG
    sudo rm -rf "$VENV_DIR"
  fi
  if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python ${py_ver} virtual environment" | tee -a $LOG
    $python -m venv "$VENV_DIR"
  fi

  echo "Updating pip" | tee -a $LOG
  echo "source $VENV_DIR/bin/activate" | tee -a $LOG
  source "$VENV_DIR/bin/activate"
  $python -m pip install --upgrade pip

  # Start with wheel which is required to compile some of the other requirements
  $python -m pip install --no-cache-dir wheel
  echo "PWD: $(pwd)" | tee -a $LOG
  ls -l aw_box/requirements.txt
  $python -m pip install --no-cache-dir -r aw_box/requirements.txt




  # VFG work to continue here

  cd `dirname "$0"`
  root_dir=`pwd`
  owner=`stat -c '%U' ${root_dir}`
  uid=`stat -c '%u' ${root_dir}`
  gid=`stat -c '%g' ${root_dir}`

  echo "9️⃣ - ..." | tee -a $LOG

  echo "🔟 - ..." | tee -a $LOG



  # HTTP server nginx
  echo "1️⃣4️⃣ - Configure HTTP server nginx" | tee -a $LOG
  # sudo sed -e "s|/opt/aw_box|${root_dir}|g" < aw_box/aw_web/nginx-site.conf > /tmp/nginx-site.conf

  # if [ $upgrade -eq 0 ]; then
  #   if [ ! -e '/etc/nginx/sites-enabled/pyaw' ]; then
  #     echo "Installing Nginx configuration file" | tee -a $LOG
  #     if [ -h '/etc/nginx/sites-enabled/default' ]; then
  #       sudo rm /etc/nginx/sites-enabled/default
  #     fi
  #     sudo mv /tmp/nginx-site.conf /etc/nginx/sites-enabled/pyaw
  #     if [ $ci_chroot -eq 0 ]; then
  #       if [[ -z "${test:-}" ]]; then
  #         sudo systemctl restart nginx
  #       fi
  #     fi
  #   else
  #     diff -q '/etc/nginx/sites-enabled/pyaw' /tmp/nginx-site.conf >/dev/null || {
  #       echo "Updating Nginx configuration file" | tee -a $LOG
  #       sudo mv /tmp/nginx-site.conf /etc/nginx/sites-enabled/pyaw
  #       if [ $ci_chroot -eq 0 ]; then
  #         if [[ -z "${test:-}" ]]; then
  #           sudo systemctl restart nginx
  #         fi
  #       fi
  #     }
  #   fi
  # else
  #   echo "Restarting Nginx" | tee -a $LOG
  #   echo "Restarting Nginx - 10/15" #> /tmp/pyaw.upgrade | tee -a $LOG
  #   if [ -e '/etc/nginx/sites-enabled/pyaw' ]; then
  #     echo "Updating Nginx configuration file" | tee -a $LOG
  #     sudo mv /tmp/nginx-site.conf /etc/nginx/sites-enabled/pyaw
  #     if [[ -z "${test:-}" ]]; then
  #       sudo systemctl restart nginx
  #     fi
  #   fi
  # fi
  # #sudo rm -f /tmp/nginx-site.conf



  # #Configure the captive portal
  # echo "1️⃣7️⃣ - Configuring the captive portal" | tee -a $LOG
  # sudo cp aw_box/config/etc/dnsmasq.d/hotspot.conf /etc/dnsmasq.d/hotspot.conf
  # if [[ -z "${test:-}" ]]; then
  #   #sudo rm /boot/firmware/network-config
  #   sudo systemctl restart dnsmasq
  #   sudo iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 -j DNAT --to-destination 192.168.2.1:80
  #   sudo iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port 80
  #   sudo iptables-save

  #   sudo netfilter-persistent save
  # fi

  # if [ $test -eq 1 ]; then
  #   aw_env/bin/python aw_box/aw_web/manage.py runserver 0.0.0.0:8000
  # fi

  # #sudo sed -e "s|/opt/aw_box|${root_dir}|g" < nabboot/nabboot.py > /tmp/nabboot.py
  # #sudo mv /tmp/nabboot.py /lib/systemd/system-shutdown/nabboot.py
  # #sudo chown root /lib/systemd/system-shutdown/nabboot.py
  # #sudo chmod +x /lib/systemd/system-shutdown/nabboot.py
fi
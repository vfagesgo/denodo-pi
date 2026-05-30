# Denodo-PI imager for Raspberry PI
This project provide a semi automated installation of Denodo Developer Tier on Raspberry PI hardware

Minimum requirements:
* Raspberry PI 4 or above (RPI 5 prefered)
* Minimum 4Gb memory 
* Micro SD card 32 Gb minimum
* Debian Linux knowledge
* Patience
* Curiosity

This documentation is aiming to provide a semi automated painful less installation of Denodo Developer Tier on Raspberry PI ARM 64 bits architecture. If you are sucessful and with a bite of luck, you should end up with with the following stack installed.

*

# Lite Raspberry PI OS Image
Raspberry PI OS Lite (64-bit) 2026-04-13
Use Raspberry PI imager
https://www.raspberrypi.com/software/

*name:* denodo-pi
*password:* denodo/password 

# Configuration flow
* Flash the SD card
* Edit */boot* from your Desktop
* First boot:
    * installs + configures cloud-init
    * enables NoCloud datasource from /boot
    * reboots
* Second boot:
    * cloud-init runs your real config (user-data)
    * loads .env
    * executes your install script

## Debugging (super useful)

**After boot:**
```
cat /boot/firstrun.log
cat /var/log/1_cloud-init-output.log
cat /var/log/2-bootstrap.log
cat /var/log/3-denodo_init.log
cat /var/log/4-denodo_install.log
```

# Install the SD Card
create a wifi password



# Cloud-init
This is used to initialise the image

Reset cloud-init with the following command
```
sudo cloud-init clean
sudo reboot
```

## On boot, cloud-init will:

* Read /boot/meta-data + user-data
* Install packages
* Create /usr/local/bin/bootstrap.sh
* Execute it
* Load your .env
* Run your init.sh

# Pre install Check
sudo raspi-config


# Note for debug

/opt/denodo-pi/git fetch origin
/opt/denodo-pi/git reset --hard origin/main
/opt/denodo-pi/chmod +x install.sh 
/opt/denodo-pi/ ./install.sh


# install flask
sudo apt-get update --fix-missing
pip3 install flask

# install RaspiWifi
https://github.com/jasbur/RaspiWiFi
sudo apt install git
git clone https://github.com/jasbur/RaspiWiFi.git

cd RaspiWiFi
sudo python3 initial_setup.py

Change the Layout of the config app
/usr/lib/raspiwifi/configuration_app

config
/etc/raspiwifi/raspiwifi.conf



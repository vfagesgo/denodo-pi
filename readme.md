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

* Denodo VDP
* Denodo Design Studio
* Denodo Data MarketPlace
* Denodo AISDK
* Denodo Sample Chabot
* Nginx HTTP server with link to all the tools

# Installation flow

## Options

Before to get started, you might be in one of the other cases. 
* Either you already have a Denodo RPI disk image with the software stack already installed and in that case you will only need to apply your Denodo license file and configure the WiFi network.
* Alternatively you need to build the image from scratch and then pocessed by flashing a new SD Card with a PI OS image. 

## Quick-Start

If you already have a an SD Card with the disk image, you only focus on the section to configure  ```network-config``` , ```denodo/denodo_config.env``` and the **AI-SDK**

You can then directly access the platform via the following URL http://denodo-pi.local

## Lite Raspberry PI OS Image
First you need to obtain a copy of **Raspberry PI OS Lite (64-bit) 2026-04-13**

You can use [**Use Raspberry PI imager**](https://www.raspberrypi.com/software/) to Create a user 

* *host name:* **denodo-pi**
* *user:* **denodo** 
* *password:* **password** 

**Denodo Application User**
*  *user:* **admin** 
*  *password:* **admin** 

## Configuration flow

* Flash the SD card
* Open the SD card from your Desktop machine **bootfs**
* Copy to the SD card the following files from the **/boot** folder of the project
    * meta-data
    * user-data
    * network-config
    * the full content of the **/boot/denodo** folder

### Edit the ```network-config```
Replace the **\<SSID\>** and **\<Password\>** with your Wifi SSID and Password

### Edit the ```denodo/denodo_config.env```

| Variable | Description|
|----------|------------|
|GITHUB_TOKEN|Github token to pull **/vfagesgo/denodo-pi.git** |
|DENODO_SUPPORT_CI|Your Denodo support CLIENT_ID to download in CLI the Denodo Binaries|
|DENODO_SUPPORT_SECRET|Your Denodo support SECRET|
|DENODO_UPDATE| The Denodo 9 update version to be installed (denodo-update-9.4.4)|
|DENODO_LIC|The name of your Denodo Developer licence file that must be place under /denodo|

### Configure the AI-SDK and Sample Chatbot

Rename and update the following AI-SDK and Sample Chatbot config files under **/denodo**:
* sdk_config.env.example to  sdk_config.env
* chatbot_config.env.example to  chatbot_config.env

### Run automatic Install

Once the SDCard configuration is completed, inser the card in your RasberryPI and power it up. **The first boot will take about 45min to fully comlplete the setup (depending of your Internet connextion speed)**

* First boot:
    * installs + configures RPI cloud-init
    * enables NoCloud datasource from /boot
    * reboots
* Second boot:
    * cloud-init runs your real config (user-data)
    * loads .env
    * executes your install script

**During the installation you can connect to the machine using **ssh**

```
ssh denodo@denodo-pi.local
```



### Debugging Commands (super useful)

**After boot:**
```
cat /boot/firstrun.log
cat /var/log/1_cloud-init-output.log
cat /var/log/2-bootstrap.log
cat /var/log/3-denodo_init.log
cat /var/log/4-denodo_install.log
```



**Cloud-init**

This is used to initialise the image
Reset cloud-init with the following command
```
sudo cloud-init clean
sudo reboot
```
**Pre install Check**

```
sudo raspi-config
```

**Note for debug**

```
/opt/denodo-pi/git fetch origin
/opt/denodo-pi/git reset --hard origin/main
/opt/denodo-pi/chmod +x install.sh 
/opt/denodo-pi/ ./install.sh
```

**Clone SD Card Image on MAC OS

Step 1: Insert SD card and find it
diskutil list
Step 2: Unmount the disk (NOT eject)
diskutil unmountDisk /dev/disk5

Step 3: Create image backup
 sudo dd if=/dev/rdisk5 of=raspberrypi.img bs=4m status=progress

Step 4: Restore to another SD card

diskutil list
diskutil unmountDisk /dev/disk5

sudo dd if=Denodo-pi-img-raw.dmg of=/dev/rdisk5 bs=4m status=progress
sync
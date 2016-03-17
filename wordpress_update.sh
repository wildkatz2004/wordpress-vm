#!/bin/bash
#
## Tech and Me ## - ©2016, https://www.techandme.se/
#
# Tested on Ubuntu Server 14.04.
#

THEME_NAME=""

# Must be root
[[ `id -u` -eq 0 ]] || { echo "Must be root to run script, in Ubuntu type: sudo -i"; exit 1; }

# System Upgrade
sudo apt-get update
sudo aptitude full-upgrade -y

# Set secure permissions
FILE="/var/scripts/wp-permissions.sh"
if [ -f $FILE ];
then
        echo "Script exists"
else
        mkdir -p /var/scripts
        wget https://raw.githubusercontent.com/enoch85/wordpress-vm/master/wp_permissions.sh -P /var/scripts/
fi
sudo bash /var/scripts/wp_permissions.sh

# Cleanup un-used packages
sudo apt-get autoremove -y
sudo apt-get autoclean

# Update GRUB, just in case
sudo update-grub

# Write to log
touch /var/log/cronjobs_success.log
echo "WORDPRESS UPDATE success-`date +"%Y%m%d"`" >> /var/log/cronjobs_success.log

# Un-hash this if you want the system to reboot
# sudo reboot

exit 0

#!/bin/bash
#
## Tech and Me ## - ©2016, https://www.techandme.se/
#
# Tested on Ubuntu Server 14.04.
#

WPATH=/var/www/html/wordpress

# Must be root
[[ `id -u` -eq 0 ]] || { echo "Must be root to run script, in Ubuntu type: sudo -i"; exit 1; }

# System Upgrade
sudo apt-get update -q2
sudo aptitude full-upgrade -y
cd $WPATH
wp db export mysql_backup.sql --allow-root
mv $WPATH/mysql_backup.sql /var/www/html/mysql_backup.sql
chown root:root /var/www/html/mysql_backup.sql
wp core update --force --allow-root
wp plugin update --all --allow-root
wp core update-db --allow-root
wp db optimize --allow-root
echo
echo "This is the current version installed:"
echo
wp core version --extra --allow-root
sleep 5

# Set secure permissions
FILE="/var/scripts/wp-permissions.sh"
if [ -f $FILE ];
then
        echo "Script exists"
else
        mkdir -p /var/scripts
        wget -q https://raw.githubusercontent.com/enoch85/wordpress-vm/master/wp-permissions.sh -P /var/scripts/
fi
sudo bash /var/scripts/wp-permissions.sh

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

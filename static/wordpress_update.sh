#!/bin/bash
#
## Tech and Me ## - ©2017, https://www.techandme.se/
#
# Tested on Ubuntu Server 14.04 and 16.04.
#

WPATH=/var/www/html/wordpress

# Must be root
[[ `id -u` -eq 0 ]] || { echo "Must be root to run script, in Ubuntu type: sudo -i"; exit 1; }

# System Upgrade
apt update -q2
apt dist-upgrade -y
wp cli update --allow-root
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

# Set secure permissions
if [ -f /var/scripts/wp-permissions.sh ]
then
        echo "Script exists"
else
        mkdir -p /var/scripts
        wget -q https://raw.githubusercontent.com/techandme/wordpress-vm/master/static/wp-permissions.sh -P /var/scripts/
fi
bash /var/scripts/wp-permissions.sh

# Cleanup un-used packages
apt autoremove -y
apt autoclean

# Update GRUB, just in case
update-grub

# Write to log
touch /var/log/cronjobs_success.log
echo "WORDPRESS UPDATE success-`date +"%Y%m%d"`" >> /var/log/cronjobs_success.log

# Un-hash this if you want the system to reboot
# reboot

exit

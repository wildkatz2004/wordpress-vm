#!/bin/bash

# Tech and Me © - 2017, https://www.techandme.se/

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/refactor/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/wordpress_update.sh\n" "$SCRIPTS"
    exit 1
fi

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

#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
WPDB=1 && MYCNFPW=1 && FIRST_IFACE=1 && CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)
unset FIRST_IFACE
unset CHECK_CURRENT_REPO
unset MYCNFPW
unset WPDB

## If you want debug mode, please activate it further down in the code at line ~60

is_root() {
    if [[ "$EUID" -ne 0 ]]
    then
        return 1
    else
        return 0
    fi
}

network_ok() {
    echo "Testing if network is OK..."
    service networking restart
    if wget -q -T 20 -t 2 http://github.com -O /dev/null
    then
        return 0
    else
        return 1
    fi
}

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash $SCRIPTS/wordpress-startup-script.sh\n"
    exit 1
fi

# Check network
if network_ok
then
    printf "${Green}Online!${Color_Off}\n"
else
    echo "Setting correct interface..."
    [ -z "$IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
    # Set correct interface
    {
        sed '/# The primary network interface/q' /etc/network/interfaces
        printf 'auto %s\niface %s inet dhcp\n# This is an autoconfigured IPv6 interface\niface %s inet6 auto\n' "$IFACE" "$IFACE" "$IFACE"
    } > /etc/network/interfaces.new
    mv /etc/network/interfaces.new /etc/network/interfaces
    service networking restart
    # shellcheck source=lib.sh
    CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)
    unset CHECK_CURRENT_REPO
fi

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check network
if network_ok
then
    printf "${Green}Online!${Color_Off}\n"
else
    printf "\nNetwork NOT OK. You must have a working Network connection to run this script.\n"
    echo "Please report this issue here: $ISSUES"
    exit 1
fi



echo
echo "Getting scripts from GitHub to be able to run the first setup..."
# All the shell scripts in static (.sh)
download_static_script security
download_static_script update
download_static_script ip
download_static_script test_connection
download_static_script wp-permissions
download_static_script change_mysql_pass
download_static_script techandme
download_static_script index
download_le_script activate-ssl

# Make $SCRIPTS excutable
chmod +x -R $SCRIPTS
chown root:root -R $SCRIPTS

# Allow wordpress to run figlet script
chown wordpress:wordpress $SCRIPTS/techandme.sh

clear
cat << EOMSTART
+---------------------------------------------------------------+
|   This script will do the final setup for you                 |
|   Scipt was created to configure Unbuntu 16.04                |   
|                                                               |
|   - Genereate new server SSH keys				                |
|                                                               |
|   - Create a new WP user                                      |
|   - Upgrade the system                                        |
|   - Activate SSL (Let's Encrypt)                              |
|   - Install phpMyadmin				                        |
|                                                               |
|                                                               |
|   - Set new password to the Linux system (user: wordpress)	|
|								                                |
|    ################# Wordpress - 2018 #################	    |
+---------------------------------------------------------------+
EOMSTART
any_key "Press any key to start the script..."
clear

# Generate new SSH Keys
printf "\nGenerating new SSH keys for the server...\n"
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Generate new MARIADB password
echo "Generating new MARIADB password..."
if bash "$SCRIPTS/change_mysql_pass.sh" && wait
then
   rm "$SCRIPTS/change_mysql_pass.sh"
fi

whiptail --title "Which apps do you want to install?" --checklist --separate-output "Automatically configure and install selected apps\nSelect by pressing the spacebar" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Fail2ban" "(Extra Bruteforce protection)   " OFF \
"Redis Cache" "(Caching)       " OFF \
"Webmin" "(Server GUI)       " OFF \
"phpMyadmin" "(*SQL GUI)       " OFF 2>results
while read -r -u 9 choice
do
    case $choice in
        Fail2ban)
            run_app_script fail2ban

        ;;
        
        Redis Cache)
            run_app_script webmin

        ;;

        Webmin)
            run_app_script webmin

        ;;

        phpMyadmin)
            run_app_script phpmyadmin_install_ubuntu16
        ;;

        *)
        ;;
    esac
done 9< results
rm -f results
clear

# Add extra security
if [[ "yes" == $(ask_yes_or_no "Do you want to add extra security, based on this: http://goo.gl/gEJHi7 ?") ]]
then
    bash $SCRIPTS/security.sh
    rm "$SCRIPTS"/security.sh
else
    echo
    echo "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/security.sh"
    any_key "Press any key to continue..."
fi
clear

cat << LETSENC
+-----------------------------------------------+
|  The following script will install a trusted  |
|  SSL certificate through Let's Encrypt.       |
+-----------------------------------------------+
LETSENC
# Let's Encrypt
if [[ "yes" == $(ask_yes_or_no "Do you want to install SSL?") ]]
then
    bash $SCRIPTS/activate-ssl.sh
else
    echo
    echo "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/activate-ssl.sh"
    any_key "Press any key to continue..."
fi

# Define FQDN and create new WP user
MYANSWER="no"
while [ "$MYANSWER" == "no" ] 
do
   clear
   cat << ENTERNEW
+-----------------------------------------------+
|    Please define the FQDN and create a new    |
|    user for Wordpress.                        |
|    Make sure your FQDN starts with either     |
|    http:// or https://, otherwise your        |
|    installation will not work correctly!      |
+-----------------------------------------------+
ENTERNEW
   echo "Enter FQDN (http(s)://yourdomain.com):"
   read -r FQDN
   echo
   echo "Enter username:"
   read -r USER
   echo
   echo "Enter password:"
   read -r NEWWPADMINPASS
   echo
   echo "Enter email address:"
   read -r EMAIL
   echo
   MYANSWER=$(ask_yes_or_no "Is this correct?  FQDN: $FQDN User: $USER Password: $NEWWPADMINPASS Email: $EMAIL") 
done
clear

echo "$FQDN" > fqdn.txt
wp option update siteurl < fqdn.txt --allow-root --path="$WPATH"
rm fqdn.txt

OLDHOME=$(wp option get home --allow-root --path="$WPATH")
wp search-replace "$OLDHOME" "$FQDN" --precise --all-tables --path="$WPATH" --allow-root

wp user create "$USER" "$EMAIL" --role=administrator --user_pass="$NEWWPADMINPASS" --path="$WPATH" --allow-root
wp user delete 1 --allow-root --reassign="$USER" --path="$WPATH"
{
echo "WP USER: $USER"
echo "WP PASS: $NEWWPADMINPASS"
} > /var/adminpass.txt


# Show current administrators
echo
echo "This is the current administrator(s):"
wp user list --role=administrator --path="$WPATH" --allow-root
any_key "Press any key to continue..."
clear

# Fixes https://github.com/techandme/wordpress-vm/issues/58
a2dismod status
service apache2 reload

# Cleanup 1
rm -f "$SCRIPTS/ip.sh"
rm -f "$SCRIPTS/test_connection.sh"
rm -f "$SCRIPTS/instruction.sh"
rm -f "$SCRIPTS/wordpress-startup-script.sh"
find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name '*.zip*' \) -delete
sed -i "s|instruction.sh|techandme.sh|g" "/home/$UNIXUSER/.bash_profile"

truncate -s 0 \
    /root/.bash_history \
    "/home/$UNIXUSER/.bash_history" \
    /var/spool/mail/root \
    "/var/spool/mail/$UNIXUSER" \
    /var/log/apache2/access.log \
    /var/log/apache2/error.log \
    /var/log/cronjobs_success.log

sed -i "s|sudo -i||g" "/home/$UNIXUSER/.bash_profile"
cat << RCLOCAL > "/etc/rc.local"
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0

RCLOCAL
clear

# Upgrade system
echo "System will now upgrade..."
bash $SCRIPTS/update.sh

# Cleanup 2
apt autoremove -y
apt autoclean
CLEARBOOT=$(dpkg -l linux-* | awk '/^ii/{ print $2}' | grep -v -e "$(uname -r | cut -f1,2 -d"-")" | grep -e "[0-9]" | xargs sudo apt -y purge)
echo "$CLEARBOOT"

ADDRESS2=$(grep "address" /etc/network/interfaces | awk '$1 == "address" { print $2 }')
# Success!
clear
printf "%s\n""${Green}"
echo    "+--------------------------------------------------------------------+"
echo    "|      Congratulations! You have successfully installed Wordpress!   |"
echo    "|                                                                    |"
printf "|         ${Color_Off}Login to Wordpress in your browser: ${Cyan}\"$ADDRESS2\"${Green}         |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}Publish your server online! ${Cyan}https://goo.gl/iUGE2U${Green}          |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}To login to MySQL just type: ${Cyan}'mysql -u root'${Green}             |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}To update this VM just type: ${Green}                              |\n"
printf "|         ${Cyan}'sudo bash /var/scripts/update.sh'${Green}                         |\n"
echo    "|                                                                    |"
printf "|    ${IRed}#################### D&B Consulting - 2018 ####################${Green}    |\n"
echo    "+--------------------------------------------------------------------+"
printf "${Color_Off}\n"

# Prefer IPv6
sed -i "s|precedence ::ffff:0:0/96  100|#precedence ::ffff:0:0/96  100|g" /etc/gai.conf

## Reboot
echo "Installations finished. System will now reboot..."
sleep 10
reboot

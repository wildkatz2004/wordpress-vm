#!/bin/bash

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/fail2ban.sh\n" "$SCRIPTS"
    sleep 3
    exit 1
fi

### Local variables ###
# location of Nextcloud logs
AUTHLOG="/var/log/auth.log"
# time to ban an IP that exceeded attempts
BANTIME_=600000
# cooldown time for incorrect passwords
FINDTIME_=1800
#bad attempts before banning an IP
MAXRETRY_=10

echo "Installing Fail2ban..."

apt update -q4 & spinner_loading
check_command apt install fail2ban -y
check_command update-rc.d fail2ban disable

# Install WP-Fail2ban and activate conf
cd $WPATH
wp plugin install --allow-root wp-fail2ban --activate
curl https://plugins.svn.wordpress.org/wp-fail2ban/trunk/filters.d/wordpress-hard.conf > /etc/fail2ban/filter.d/wordpress.conf

if [ ! -f $AUTHLOG ]
then
    echo "$AUTHLOG not found"
    exit 1
fi

# Create jail.local file
cat << FCONF > /etc/fail2ban/jail.d/wordpress.conf
# The DEFAULT allows a global definition of the options. They can be overridden
# in each jail afterwards.
[DEFAULT]

# "ignoreip" can be an IP address, a CIDR mask or a DNS host. Fail2ban will not
# ban a host which matches an address in this list. Several addresses can be
# defined using space separator.
ignoreip = 127.0.0.1/8 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8

#
# ACTIONS
#
banaction = iptables-multiport
protocol = tcp
chain = INPUT
action_ = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mw = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mwl = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action = %(action_)s

#
# HTTP servers
#

[wordpress]
enabled  = true
port     = http,https
filter   = wordpress
logpath  = $AUTHLOG
maxretry = $MAXRETRY_
findtime = $FINDTIME_
bantime  = $BANTIME_
FCONF

cat << SCONF > /etc/fail2ban/jail.d/modsec.conf
# Fail2Ban configuration file
#
# Author: Florian Roth

[Definition]
failregex = \[.*?\]\s[\w-]*\s<HOST>\s
ignoreregex =
SCONF

cat <<EOT >> /etc/fail2ban/jail.conf
[modsec]
enabled  = true
filter   = modsec
action   = iptables-multiport[name=ModSec, port="http,https"]
#           sendmail-buffered[name=ModSec, lines=5, dest=you@mail.com]
logpath  = /var/log/apache2/modsec_audit.log
bantime  = 172800
maxretry = 1
EOT

# Update settings
check_command update-rc.d fail2ban defaults
check_command update-rc.d fail2ban enable
check_command service fail2ban restart

# The End
echo
echo "Fail2ban is now sucessfully installed."
echo "Please use 'fail2ban-client set wordpress unbanip <Banned IP>' to unban certain IPs"
echo "You can also use 'iptables -L -n' to check which IPs that are banned"
any_key "Press any key to continue..."
clear

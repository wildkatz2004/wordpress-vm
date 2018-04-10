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

if [[ "no" == $(ask_yes_or_no "Do you want to create a new user?") ]]
then
    echo "Not adding another user..."
    sleep 1
else
    read -r -p "Enter name of the new user: " NEWUSER
    useradd -m "$NEWUSER" -G sudo
    while true
    do
        sudo passwd "$NEWUSER" && break
    done
    sudo -u "$NEWUSER" sudo bash wordpress_install.sh
fi

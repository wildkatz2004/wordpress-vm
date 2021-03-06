#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
MYCNFPW=1 . <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)
unset MYCNFPW

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode
change_mysql_pass(){
# Change MARIADB Password
if mysqladmin -u root -p"$MARIADBMYCNFPASS" password "$NEWMARIADBPASS" > /dev/null 2>&1
then
    echo -e "${Green}Your new MARIADB root password is: $NEWMARIADBPASS${Color_Off}"
    cat << LOGIN > "$MYCNF"
[client]
password='$NEWMARIADBPASS'
LOGIN
    chmod 0600 $MYCNF
    exit 0
else
    echo "Changing MARIADB root password failed."
    echo "Your old password is: $MARIADBMYCNFPASS"
    exit 1
fi
}
change_mysql_pass


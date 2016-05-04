#!bin/bash

# Tech and Me, ©2016 - www.techandme.se

SHUF=$(shuf -i 17-20 -n 1)
NEWMYSQLPASS=$(cat /dev/urandom | tr -dc "a-zA-Z0-9@#*=" | fold -w $SHUF | head -n 1)
PW_FILE=/var/mysql_password.txt
OLDMYSQL=$(sed -n -e 's/^.*MySQL root password: //p' $PW_FILE)

echo "Generating new MySQL root password..."
# Change MySQL password
mysqladmin -u root -p$OLDMYSQL password $NEWMYSQLPASS > /dev/null 2>&1
if [ $? -eq 0 ]
then
        echo -e "\e[32mYour new MySQL ROOT password is: $NEWMYSQLPASS\e[0m"
        echo
	echo "New MySQL ROOT password: $NEWMYSQLPASS" >> $PW_FILE
else
        echo "Changing MySQL ROOT password failed."
        echo "Your old password is: $OLDMYSQL"
fi
sleep 1

exit 0


#!/bin/bash

# Prefer IPv4
sed -i "s|#precedence ::ffff:0:0/96  100|precedence ::ffff:0:0/96  100|g" /etc/gai.conf

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
FIRST_IFACE=1 && CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)
unset FIRST_IFACE
unset CHECK_CURRENT_REPO

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/wordpress_install.sh\n" "$SCRIPTS"
    exit 1
fi

# Test RAM size (2GB min) + CPUs (min 1)
ram_check 2 Wordpress
cpu_check 1 Wordpress

# Show current user
echo
echo "Current user with sudo permissions is: $UNIXUSER".
echo "This script will set up everything with that user."
echo "If the field after ':' is blank you are probably running as a pure root user."
echo "It's possible to install with root, but there will be minor errors."
echo
echo "Please create a user with sudo permissions if you want an optimal installation."
run_static_script adduser

# Check Ubuntu version
echo "Checking server OS and version..."
if [ "$OS" != 1 ]
then
    echo "Ubuntu Server is required to run this script."
    echo "Please install that distro and try again."
    exit 1
fi


if ! version 16.04 "$DISTRO" 16.04.4; then
    echo "Ubuntu version $DISTRO must be between 16.04 - 16.04.4"
    exit
fi


MYSQL=$(dpkg-query -W -f='${Status}' mysql-server 2>/dev/null | grep -c "ok installed")
  if [ $(dpkg-query -W -f='${Status}' mysql-server 2>/dev/null | grep -c "ok installed") -eq 0 ];
  then
    echo -e "${YELLOW}Installing mysql-server${NC}"
    apt-get install mysql-server --yes;
    elif [ $(dpkg-query -W -f='${Status}' mysql-server 2>/dev/null | grep -c "ok installed") -eq 1 ];
    then
      echo -e "${GREEN}mysql-server is installed!${NC}"
  fi

# Create $SCRIPTS dir
if [ ! -d "$SCRIPTS" ]
then
    mkdir -p "$SCRIPTS"
fi

# Check network
if ! [ -x "$(command -v nslookup)" ]
then
    apt install dnsutils -y -q
fi
if ! [ -x "$(command -v ifup)" ]
then
    apt install ifupdown -y -q
fi
sudo ifdown "$IFACE" && sudo ifup "$IFACE"
if ! nslookup google.com
then
    echo "Network NOT OK. You must have a working Network connection to run this script."
    exit 1
fi

# Update system
apt update -q4 & spinner_loading

# mysql_secure_installation
sudo apt-get -y install expect

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root:\"
send \"$MARIADB_PASS\r\"
expect \"Would you like to setup VALIDATE PASSWORD plugin?\"
send \"n\r\" 
expect \"Change the password for root ?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

echo "$SECURE_MYSQL"

apt-get -y purge expect

# Install VM-tools
apt install open-vm-tools -y

# Install Apache
apt install apache2 -y
a2enmod rewrite \
        headers \
        env \
        dir \
        mime \
        ssl \
        setenvif

# Install PHP 7.0
apt install -y \
        php \
	libapache2-mod-php \
	php-mcrypt \
	php-pear \
	php-mbstring \
	php-mysql \
	php-soap \
	php-zip

# Download wp-cli.phar to be able to install Wordpress
check_command curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Create dir
mkdir $WPATH

# Create wp-cli.yml
touch $WPATH/wp-cli.yml
cat << YML_CREATE > "$WPATH/wp-cli.yml"
apache_modules:
  - mod_rewrite
YML_CREATE

# Show info about wp-cli
wp --info --allow-root

# Download Wordpress
cd "$WPATH"
check_command wp core download --allow-root --force --debug --path="$WPATH"

# Populate DB
mysql -uroot -p"$MARIADB_PASS" <<MYSQL_SCRIPT
CREATE DATABASE $WPDBNAME;
CREATE USER '$WPDBUSER'@'localhost' IDENTIFIED BY '$WPDBPASS';
GRANT ALL PRIVILEGES ON $WPDBNAME.* TO '$WPDBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
wp core config --allow-root --dbname=$WPDBNAME --dbuser=$WPDBUSER --dbpass="$WPDBPASS" --dbhost=localhost --extra-php <<PHP
define( 'WP_DEBUG', false );
define( 'WP_CACHE_KEY_SALT', 'wpredis_' );
define( 'WP_REDIS_MAXTTL', 9600);
define( 'WP_REDIS_SCHEME', 'unix' );
define( 'WP_REDIS_PATH', '/var/run/redis/redis.sock' );
define( 'WP_REDIS_PASSWORD', '$REDIS_PASS' );
define( 'WP_AUTO_UPDATE_CORE', true );
PHP

# Make sure the passwords are the same, this file will be deleted when Redis is run.
echo "$REDIS_PASS" > /tmp/redis_pass.txt

# Install Wordpress
check_command wp core install --allow-root --url=http://"$ADDRESS"/ --title=Wordpress --admin_user=$WPADMINUSER --admin_password="$WPADMINPASS" --admin_email=no-reply@techandme.se --skip-email
echo "WP PASS: $WPADMINPASS" > /var/adminpass.txt
chown wordpress:wordpress /var/adminpass.txt

# Create welcome post
check_command wget -q $STATIC/welcome.txt
sed -i "s|wordpress_user_login|$WPADMINUSER|g" welcome.txt
sed -i "s|wordpress_password_login|$WPADMINPASS|g" welcome.txt
wp post create ./welcome.txt --post_title='Tech and Me - Welcome' --post_status=publish --path=$WPATH --allow-root
rm -f welcome.txt
wp post delete 1 --force --allow-root

# Show version
wp core version --allow-root
sleep 3

# Install Apps

wp plugin install --allow-root wp-mail-smtp --activate

# set pretty urls
wp rewrite structure '/%postname%/' --hard --allow-root
wp rewrite flush --hard --allow-root

# delete akismet and hello dolly
wp plugin delete akismet --allow-root
wp plugin delete hello --allow-root

# Secure permissions
run_static_script wp-permissions

# Hardening security
# create .htaccess to protect uploads directory
cat > $WPATH/wp-content/uploads/.htaccess <<'EOL'
# Protect this file
<Files .htaccess>
Order Deny,Allow
Deny from All
</Files>
# whitelist file extensions to prevent executables being
# accessed if they get uploaded
order deny,allow
deny from all
<Files ~ ".(docx?|xlsx?|pptx?|txt|pdf|xml|css|jpe?g|png|gif)$">
allow from all
</Files>
EOL

# Change values in php.ini (increase max file size)
# max_execution_time
sed -i "s|max_execution_time =.*|max_execution_time = 3500|g" /etc/php/7.0/apache2/php.ini
# max_input_time
sed -i "s|max_input_time =.*|max_input_time = 3600|g" /etc/php/7.0/apache2/php.ini
# memory_limit
sed -i "s|memory_limit =.*|memory_limit = 512M|g" /etc/php/7.0/apache2/php.ini
# post_max
sed -i "s|post_max_size =.*|post_max_size = 1100M|g" /etc/php/7.0/apache2/php.ini
# upload_max
sed -i "s|upload_max_filesize =.*|upload_max_filesize = 1000M|g" /etc/php/7.0/apache2/php.ini

# Install Figlet
apt install figlet -y

# Generate $SSL_CONF
if [ ! -f $SSL_CONF ];
        then
        touch $SSL_CONF
        cat << SSL_CREATE > $SSL_CONF
<VirtualHost *:443>
    Header add Strict-Transport-Security: "max-age=15768000;includeSubdomains"
    SSLEngine on

### YOUR SERVER ADDRESS ###
#    ServerAdmin admin@example.com
#    ServerName example.com
#    ServerAlias www.example.com

### SETTINGS ###
    DocumentRoot $WPATH
    <Directory $WPATH>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
    </Directory>

    SetEnv HOME $WPATH
    SetEnv HTTP_HOME $WPATH

### LOCATION OF CERT FILES ###
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

#    SSLCertificateFile /etc/ssl/example.com/certificate.crt
#    SSLCertificateKeyFile /etc/ssl/example.com/ssl_example_com_se.key
#    SSLCACertificateFile /etc/ssl/example.com/certificate.ca.crt
#    SSLCertificateChainFile /etc/crt/example_com.ca-bundle

</VirtualHost>
SSL_CREATE
echo "$SSL_CONF was successfully created"
sleep 3
fi

# Generate $HTTP_CONF
if [ ! -f $HTTP_CONF ];
        then
        touch $HTTP_CONF
        cat << HTTP_CREATE > $HTTP_CONF

<VirtualHost *:80>

### YOUR SERVER ADDRESS ###
#    ServerAdmin admin@example.com
#    ServerName example.com
#    ServerAlias www.example.com

### SETTINGS ###
    DocumentRoot $WPATH
    <Directory $WPATH>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
    </Directory>

</VirtualHost>
HTTP_CREATE
echo "$HTTP_CONF was successfully created"
sleep 3
fi

# Enable new config
a2ensite wordpress_port_443.conf
a2ensite wordpress_port_80.conf
a2dissite 000-default.conf
a2dissite default-ssl.conf
service apache2 restart


# Enable OPCache for PHP
phpenmod opcache
{
echo "# OPcache settings for Wordpress"
echo "opcache.enable=1"
echo "opcache.enable_cli=1"
echo "opcache.interned_strings_buffer=8"
echo "opcache.max_accelerated_files=10000"
echo "opcache.memory_consumption=128"
echo "opcache.save_comments=1"
echo "opcache.revalidate_freq=1"
echo "opcache.validate_timestamps=1"
} >> /etc/php/7.0/apache2/php.ini

# Install Redis
run_static_script redis-server-ubuntu16

# Set secure permissions final
run_static_script wp-permissions

# Prepare for first mount
download_static_script instruction
download_static_script history
run_static_script change-root-profile
run_static_script change-wordpress-profile
if [ ! -f "$SCRIPTS"/wordpress-startup-script.sh ]
then
check_command wget -q "$GITHUB_REPO"/wordpress-startup-script.sh -P "$SCRIPTS"
fi

# Make $SCRIPTS excutable
chmod +x -R "$SCRIPTS"
chown root:root -R "$SCRIPTS"

# Allow wordpress to run theese scripts
chown wordpress:wordpress "$SCRIPTS/instruction.sh"
chown wordpress:wordpress "$SCRIPTS/history.sh"

# Upgrade
apt dist-upgrade -y

# Remove LXD (always shows up as failed during boot)
apt purge lxd -y

# Cleanup
CLEARBOOT=$(dpkg -l linux-* | awk '/^ii/{ print $2}' | grep -v -e ''"$(uname -r | cut -f1,2 -d"-")"'' | grep -e '[0-9]' | xargs sudo apt -y purge)
echo "$CLEARBOOT"
apt autoremove -y
apt autoclean
find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name '*.zip*' \) -delete

# Prefer IPv6
sed -i "s|precedence ::ffff:0:0/96  100|#precedence ::ffff:0:0/96  100|g" /etc/gai.conf

# Reboot
echo "Installation done, system will now reboot..."
reboot

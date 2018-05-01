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

preinstall_lamp
# Check if it's a clean server
is_this_installed postgresql
is_this_installed apache2
is_this_installed php
is_this_installed mysql-common
is_this_installed mysql-server

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

#Changing local timezone to Central Standard
sudo timedatectl set-timezone America/Mexico_City
# Update system
apt update -q4 & spinner_loading

# Write MySQL pass to file and keep it safe
{
echo "[client]"
echo "password='$MARIADB_PASS'"
} > "$MYCNF"
chmod 0600 $MYCNF
chown root:root $MYCNF

# Install MySQL 5.7
#export DEBIAN_FRONTEND="noninteractive"
#apt install software-properties-common -y
#sudo apt-key adv --keyserver pgp.mit.edu --recv-keys 5072E1F5
#sudo add-apt-repository 'deb http://repo.mysql.com/apt/ubuntu/ trusty mysql-5.7'
#sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MARIADB_PASS"
#sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MARIADB_PASS"
#apt update -q4 & spinner_loading
#check_command apt-get install mysql-server -y

# Install MARIADB
export DEBIAN_FRONTEND=noninteractive
sudo apt-get install software-properties-common
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
sudo add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://sfo1.mirrors.digitalocean.com/mariadb/repo/10.2/ubuntu xenial main'
sudo debconf-set-selections <<< "mariadb-server-10.2 mysql-server/root_password password $MARIADB_PASS"
sudo debconf-set-selections <<< "mariadb-server-10.2 mysql-server/root_password_again password $MARIADB_PASS"
apt update -q4 & spinner_loading
check_command apt install mariadb-server-10.2 -y

# https://blog.v-gar.de/2018/02/en-solved-error-1698-28000-in-mysqlmariadb/
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET plugin='' WHERE user='root';"
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET password=PASSWORD('$MARIADB_PASS') WHERE user='root';"
mysql -u root -p"$MARIADB_PASS" -e "flush privileges;"

# mysql_secure_installation
apt -y install expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$MARIADB_PASS\r\"
expect \"Change the root password?\"
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
apt -y purge expect

# Write a new MariaDB config
run_static_script new_etc_mycnf


# Install Apache
check_command apt install apache2 -y

a2enmod rewrite \
        headers \
        env \
        dir \
        mime \
        ssl \
        setenvif 



# Install PHP 7.0
check_command apt update -q4 & spinner_loading
check_command apt-get -y install php-dev libapache2-mod-fastcgi php7.0-fpm php7.0
check_command apt-get -y install libapache2-mod-php7.0 php7.0-cli php7.0-common php7.0-mbstring php7.0-gd php7.0-intl php7.0-xml php7.0-mysql php7.0-mcrypt php7.0-zip php-pear php7.0-soap php7.0-curl php7.0-json php7.0-cgi
check_command apt-get -y install php7.0-opcache php-apcu

     if [ -f  /etc/apache2/conf-available/php7.0-fpm.conf ]; then
        mv /etc/apache2/conf-available/php7.0-fpm.conf  /etc/apache2/conf-available/php7.0-fpm.conf.bak
        sudo a2disconf php7.0-fpm.conf
     fi

cat > /etc/apache2/conf-available/php-fpm.conf  << EOF 
<IfModule mod_fastcgi.c>
  AddHandler php.fcgi .php
  Action php.fcgi /php.fcgi
  Alias /php.fcgi /usr/lib/cgi-bin/php.fcgi
  FastCgiExternalServer /usr/lib/cgi-bin/php.fcgi -socket /run/php/php7.0-fpm.sock -pass-header Authorization -idle-timeout 3600
  <Directory /usr/lib/cgi-bin>
    Require all granted
  </Directory>
</IfModule>
EOF

#enable /etc/apache2/conf-available/php-fpm.confcat
sudo a2enconf php-fpm.conf
# Next, enable the following Apache modules...
a2enmod actions fastcgi alias
# And disable this module, which is mod_php:
sudo a2dismod php7.0
# Restart Apache
systemctl restart apache2

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
check_command wp core config --allow-root --dbname=$WPDBNAME --dbuser=$WPDBUSER --dbpass="$WPDBPASS" --dbhost=localhost --extra-php <<PHP
define( 'WP_DEBUG', false );
define( 'WP_CACHE_KEY_SALT', 'wpredis_' );
define( 'WP_REDIS_MAXTTL', 9600);
define( 'WP_REDIS_SCHEME', 'tcp' );
define( 'WP_REDIS_PATH', '/var/run/redis/redis.sock' );
define( 'WP_REDIS_PASSWORD', '$REDIS_PASS' );
define( 'WP_AUTO_UPDATE_CORE', true );
define('WP_CACHE', true);
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

# delete akismet and hello dolly
wp plugin delete akismet --allow-root
wp plugin delete hello --allow-root

# Install Apps
wp plugin install --allow-root opcache
wp plugin install --allow-root wp-mail-smtp
wp plugin install --allow-root redis-cache
wp plugin install --allow-root all-in-one-wp-migration --activate

 sed -i "s|define( 'AI1WM_MAX_FILE_SIZE', 536870912 )|define( 'AI1WM_MAX_FILE_SIZE', 536870912 * 8 )|g" /var/www/html/wordpress/wp-content/plugins/all-in-one-wp-migration/constants.php


# set pretty urls
wp rewrite structure '/%postname%/' --hard --allow-root
wp rewrite flush --hard --allow-root

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
systemctl restart apache2.service


# Enable OPCache for PHP
phpenmod opcache
{
echo "# OPcache settings for Wordpress"
echo "opcache.enable=1"
echo "opcache.enable_cli=1"
echo "opcache.interned_strings_buffer=16"
echo "opcache.max_accelerated_files=7963"
echo "opcache.memory_consumption=192"
echo "opcache.revalidate_path=1"
echo "opcache.revalidate_freq=1"
echo "opcache.validate_timestamps=1"
echo "opcache.enable_file_override=0"
echo "opcache.fast_shutdown=1"
} >> /etc/php/7.0/apache2/php.ini

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

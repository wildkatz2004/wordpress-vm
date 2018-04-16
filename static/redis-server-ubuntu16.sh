#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master/lib.sh)

# Tech and Me © - 2017, https://www.techandme.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
if ! is_root
then
    echo "Must be root to run script, in Ubuntu type: sudo -i"
    exit 1
fi

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

# Check if dir exists
if [ ! -d $SCRIPTS ]
then
    mkdir -p $SCRIPTS
fi

# Install Redis

# Get packages to be able to install Redis
apt update -q4 & spinner_loading
sudo apt install -q -y \
    build-essential \
    tcl8.5 \
    php7.0-dev \
    php-pear


# Redis: Download and Extract the Source Code
cd /tmp
curl -O http://download.redis.io/redis-stable.tar.gz
tar xzvf redis-stable.tar.gz
cd redis-stable

# Build and Install Redis
make
make test
make install
make install PREFIX=/usr
mkdir /etc/redis
sudo cp /tmp/redis-stable/redis.conf /etc/redis
cd ..
rm -R redis*

adduser --system --group --disabled-login redis --no-create-home --shell /bin/nologin --quiet
usermod -g www-data redis
mkdir /var/lib/redis
chown redis:redis /var/lib/redis
chmod 770 /var/lib/redis

sed -i "s|# unixsocket /var/run/redis/redis.sock|unixsocket $REDIS_SOCK|g" $REDIS_CONF
sed -i "s|# unixsocketperm 700|unixsocketperm 777|g" $REDIS_CONF
sed -i "s|port 6379|port 0|g" $REDIS_CONF
sed -i "s|# requirepass foobared|requirepass $(cat /tmp/redis_pass.txt)|g" $REDIS_CONF
sed -i "s|# supervised no|supervised systemd|g" $REDIS_CONF
sed -i "s|# daemonize no|daemonize yes|g" $REDIS_CONF
sed -i "s|# maxmemory <bytes>|maxmemory 1288490188|g" $REDIS_CONF
sed -i "s|# maxmemory-policy noeviction|maxmemory-policy allkeys-lru|g" $REDIS_CONF
sed -i "s|# bind 127.0.0.1|bind 127.0.0.1|g" $REDIS_CONF
sed -i" s/^dir \.\//dir \/var\/lib\/redis\//" $REDIS_CONF
sed -i "s/^loglevel verbose$/loglevel notice/" $REDIS_CONF
sed -i "s/^logfile stdout$/logfile \/var\/log\/redis.log/" $REDIS_CONF

# Create a Redis systemd Unit File
cat << EOF > /etc/systemd/system/redis.service
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
ExecStop=/usr/local/bin/redis-cli shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo apt-get -y install php-redis
# Install PHPmodule
if ! pecl install -Z redis
then
    echo "PHP module installation failed"
    sleep 3
    exit 1
else
    printf "${Green}\nPHP module installation OK!${Color_Off}\n"
fi
# Set globally doesn't work for some reason
# touch /etc/php/7.0/mods-available/redis.ini
# echo 'extension=redis.so' > /etc/php/7.0/mods-available/redis.ini
# phpenmod redis
# Setting direct to apache2 works if 'libapache2-mod-php7.0' is installed
echo 'extension=redis.so' >> /etc/php/7.0/apache2/php.ini
service apache2 restart




# Redis performance tweaks
if ! grep -Fxq "vm.overcommit_memory = 1" /etc/sysctl.conf
then
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
fi

redis-cli SHUTDOWN
rm -f /tmp/redis_pass.txt

echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled

# Secure Redis
chown redis:root /etc/redis/redis.conf
chmod 600 /etc/redis/redis.conf

# Start Redis
systemctl start redis
sudo systemctl status redis
sleep 5
# Enable Redis to Start at Boot
systemctl enable redis

# Clean
rm -rf /tmp/redis-stable
rm /tmp/redis-stable.tar.gz

# Cleanup
apt purge -y \
    git \
    build-essential*

apt update -q4 & spinner_loading
apt autoremove -y
apt autoclean

exit

#!/bin/bash
# shellcheck disable=2034,2059
true
# see https://github.com/koalaman/shellcheck/wiki/Directive

## variables

# Dirs
SCRIPTS=/var/scripts
WWW_ROOT=/var/www/html
WPATH=$WWW_ROOT/wordpress
GPGDIR=/tmp/gpg

# Ubuntu OS
DISTRO=$(lsb_release -sd | cut -d ' ' -f 2)
OS=$(grep -ic "Ubuntu" /etc/issue.net)

# Network
[ ! -z "$FIRST_IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
IFACE2=$(ip -o link show | awk '{print $2,$9}' | grep 'UP' | cut -d ':' -f 1)
[ ! -z "$CHECK_CURRENT_REPO" ] && REPO=$(apt-get update | grep -m 1 Hit | awk '{ print $2}')
ADDRESS=$(curl -s -m 5 ipinfo.io/ip)
WGET="/usr/bin/wget"
WANIP4=$(curl -s -m 5 ipinfo.io/ip)
[ ! -z "$LOAD_IP6" ] && WANIP6=$(curl -s -k -m 7 https://6.ifcfg.me)
IFCONFIG="/sbin/ifconfig"
INTERFACES="/etc/network/interfaces"
NETMASK=$($IFCONFIG | grep -w inet |grep -v 127.0.0.1| awk '{print $4}' | cut -d ":" -f 2)
GATEWAY=$(route -n|grep "UG"|grep -v "UGH"|cut -f 10 -d " ")

# Repo
GITHUB_REPO="https://raw.githubusercontent.com/wildkatz2004/wordpress-vm/master"
STATIC="$GITHUB_REPO/static"
LETS_ENC="$GITHUB_REPO/lets-encrypt"
ISSUES="https://github.com/wildkatz2004/wordpress-vm/issues"
APP="$GITHUB_REPO/apps"

# User information
WPDBNAME=goodman_wordpress
WPADMINUSER=change_this_user
UNIXUSER=$SUDO_USER
UNIXUSER_PROFILE="/home/$UNIXUSER/.bash_profile"
UNIXUSER_ALIAS="/home/$UNIXUSER/.bash_alias"
ROOT_PROFILE="/root/.bash_profile"

# MARIADB
SHUF=$(shuf -i 25-29 -n 1)
MARIADB_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
WPDBPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
NEWMARIADBPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
WPDBUSER=wordpress_user
WPADMINPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
[ ! -z "$WPDB" ] && WPCONFIGDB=$(grep "DB_PASSWORD" /var/www/html/wordpress/wp-config.php | awk '{print $3}' | cut -d "'" -f2)
MYCNF=/root/.my.cnf
[ ! -z "$MYCNFPW" ] && MARIADBMYCNFPASS=$(grep "password" $MYCNF | sed -n "/password/s/^password='\(.*\)'$/\1/p")
# Path to specific files
PHPMYADMIN_CONF="/etc/apache2/conf-available/phpmyadmin.conf"
SECURE="$SCRIPTS/wp-permissions.sh"
SSL_CONF="/etc/apache2/sites-available/wordpress_port_443.conf"
HTTP_CONF="/etc/apache2/sites-available/wordpress_port_80.conf"
ETCMYCNF=/etc/mysql/my.cnf

# Letsencrypt
LETSENCRYPTPATH="/etc/letsencrypt"
CERTFILES="$LETSENCRYPTPATH/live"
DHPARAMS="$CERTFILES/$SUBDOMAIN/dhparam.pem"

# phpMyadmin
PHPMYADMINDIR=/usr/share/phpmyadmin
PHPMYADMIN_CONF="/etc/apache2/conf-available/phpmyadmin.conf"
UPLOADPATH=""
SAVEPATH=""

# Redis
REDIS_CONF=/etc/redis/redis.conf
REDIS_SOCK=/var/run/redis/redis.sock
RSHUF=$(shuf -i 30-35 -n 1)
REDIS_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$RSHUF" | head -n 1)

# Extra security
SPAMHAUS=/etc/spamhaus.wl
ENVASIVE=/etc/apache2/mods-available/mod-evasive.load
APACHE2=/etc/apache2/apache2.conf

## functions

# If script is running as root?
#
# Example:
# if is_root
# then
#     # do stuff
# else
#     echo "You are not root..."
#     exit 1
# fi
#
is_root() {
    if [[ "$EUID" -ne 0 ]]
    then
        return 1
    else
        return 0
    fi
}

debug_mode() {
if [ "$DEBUG" -eq 1 ]
then
    set -ex
fi
}

ask_yes_or_no() {
    read -r -p "$1 ([y]es or [N]o): "
    case ${REPLY,,} in
        y|yes)
            echo "yes"
        ;;
        *)
            echo "no"
        ;;
    esac
}

# Check if program is installed (is_this_installed apache2)
is_this_installed() {
if [ "$(dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    echo "${1} is installed, it must be a clean server."
    exit 1
fi
}

# Install_if_not program
install_if_not () {
if [[ "$(is_this_installed "${1}")" != "${1} is installed, it must be a clean server." ]]
then
    apt update -q4 & spinner_loading && apt install "${1}" -y
fi
}

# Test RAM size 
# Call it like this: ram_check [amount of min RAM in GB] [for which program]
# Example: ram_check 2 Wordpress
ram_check() {
mem_available="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
if [ "${mem_available}" -lt "$((${1}*1002400))" ]
then
    printf "${Red}Error: ${1} GB RAM required to install ${2}!${Color_Off}\n" >&2
    printf "${Red}Current RAM is: ("$((mem_available/1002400))" GB)${Color_Off}\n" >&2
    sleep 3
    exit 1
else
    printf "${Green}RAM for ${2} OK! ("$((mem_available/1002400))" GB)${Color_Off}\n"
fi
}

# Test number of CPU
# Call it like this: cpu_check [amount of min CPU] [for which program]
# Example: cpu_check 2 Wordpress
cpu_check() {
nr_cpu="$(nproc)"
if [ "${nr_cpu}" -lt "${1}" ]
then
    printf "${Red}Error: ${1} CPU required to install ${2}!${Color_Off}\n" >&2
    printf "${Red}Current CPU: ("$((nr_cpu))")${Color_Off}\n" >&2
    sleep 3
    exit 1
else
    printf "${Green}CPU for ${2} OK! ("$((nr_cpu))")${Color_Off}\n"
fi
}

check_command() {
  if ! eval "$*"
  then
     printf "${IRed}Sorry but something went wrong. Please report this issue to $ISSUES and include the output of the error message. Thank you!${Color_Off}\n"
     echo "$* failed"
    exit 1
  fi
}

network_ok() {
    echo "Testing if network is OK..."
    service networking restart
    if wget -q -T 20 -t 2 http://github.com -O /dev/null & spinner_loading
    then
        return 0
    else
        return 1
    fi
}

# Whiptail auto-size
calc_wt_size() {
    WT_HEIGHT=17
    WT_WIDTH=$(tput cols)

    if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
        WT_WIDTH=80
    fi
    if [ "$WT_WIDTH" -gt 178 ]; then
        WT_WIDTH=120
    fi
    WT_MENU_HEIGHT=$((WT_HEIGHT-7))
    export WT_MENU_HEIGHT
}

# Initial download of script in ../static
# call like: download_static_script name_of_script
download_static_script() {
    # Get ${1} script
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if ! { wget -q "${STATIC}/${1}.sh" -P "$SCRIPTS" || wget -q "${STATIC}/${1}.php" -P "$SCRIPTS" || wget -q "${STATIC}/${1}.py" -P "$SCRIPTS"; }
    then
        echo "{$1} failed to download. Please run: 'sudo wget ${STATIC}/${1}.sh|.php|.py' again."
        echo "If you get this error when running the wordpress-startup-script then just re-run it with:"
        echo "'sudo bash $SCRIPTS/wordpress-startup-script.sh' and all the scripts will be downloaded again"
        exit 1
    fi
}

# Initial download of script in ../lets-encrypt
# call like: download_le_script name_of_script
download_le_script() {
    # Get ${1} script
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if ! { wget -q "${LETS_ENC}/${1}.sh" -P "$SCRIPTS" || wget -q "${LETS_ENC}/${1}.php" -P "$SCRIPTS" || wget -q "${LETS_ENC}/${1}.py" -P "$SCRIPTS"; }
    then
        echo "{$1} failed to download. Please run: 'sudo wget ${STATIC}/${1}.sh|.php|.py' again."
        echo "If you get this error when running the wordpress-startup-script then just re-run it with:"
        echo "'sudo bash $SCRIPTS/wordpress-startup-script.sh' and all the scripts will be downloaded again"
        exit 1
    fi
}

# Run any script in ../master
# call like: run_main_script name_of_script
run_main_script() {
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if wget -q "${GITHUB_REPO}/${1}.sh" -P "$SCRIPTS"
    then
        bash "${SCRIPTS}/${1}.sh"
        rm -f "${SCRIPTS}/${1}.sh"
    elif wget -q "${GITHUB_REPO}/${1}.php" -P "$SCRIPTS"
    then
        php "${SCRIPTS}/${1}.php"
        rm -f "${SCRIPTS}/${1}.php"
    elif wget -q "${GITHUB_REPO}/${1}.py" -P "$SCRIPTS"
    then
        python "${SCRIPTS}/${1}.py"
        rm -f "${SCRIPTS}/${1}.py"
    else
        echo "Downloading ${1} failed"
        echo "Script failed to download. Please run: 'sudo wget ${GITHUB_REPO}/${1}.sh|php|py' again."
        sleep 3
    fi
}

# Run any script in ../static
# call like: run_static_script name_of_script
run_static_script() {
    # Get ${1} script
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if wget -q "${STATIC}/${1}.sh" -P "$SCRIPTS"
    then
        bash "${SCRIPTS}/${1}.sh"
        rm -f "${SCRIPTS}/${1}.sh"
    elif wget -q "${STATIC}/${1}.php" -P "$SCRIPTS"
    then
        php "${SCRIPTS}/${1}.php"
        rm -f "${SCRIPTS}/${1}.php"
    elif wget -q "${STATIC}/${1}.py" -P "$SCRIPTS"
    then
        python "${SCRIPTS}/${1}.py"
        rm -f "${SCRIPTS}/${1}.py"
    else
        echo "Downloading ${1} failed"
        echo "Script failed to download. Please run: 'sudo wget ${STATIC}/${1}.sh|php|py' again."
        sleep 3
    fi
}

# Run any script in ../apps
# call like: run_app_script collabora|nextant|passman|spreedme|contacts|calendar|webmin|previewgenerator
run_app_script() {
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if wget -q "${APP}/${1}.sh" -P "$SCRIPTS"
    then
        bash "${SCRIPTS}/${1}.sh"
        rm -f "${SCRIPTS}/${1}.sh"
    elif wget -q "${APP}/${1}.php" -P "$SCRIPTS"
    then
        php "${SCRIPTS}/${1}.php"
        rm -f "${SCRIPTS}/${1}.php"
    elif wget -q "${APP}/${1}.py" -P "$SCRIPTS"
    then
        python "${SCRIPTS}/${1}.py"
        rm -f "${SCRIPTS}/${1}.py"
    else
        echo "Downloading ${1} failed"
        echo "Script failed to download. Please run: 'sudo wget ${APP}/${1}.sh|php|py' again."
        sleep 3
    fi
}

version(){
    local h t v

    [[ $2 = "$1" || $2 = "$3" ]] && return 0

    v=$(printf '%s\n' "$@" | sort -V)
    h=$(head -n1 <<<"$v")
    t=$(tail -n1 <<<"$v")

    [[ $2 != "$h" && $2 != "$t" ]]
}

version_gt() {
    local v1 v2 IFS=.
    read -ra v1 <<< "$1"
    read -ra v2 <<< "$2"
    printf -v v1 %03d "${v1[@]}"
    printf -v v2 %03d "${v2[@]}"
    [[ $v1 > $v2 ]]
}

spinner_loading() {
    pid=$!
    spin='-\|/'
    i=0
    while kill -0 $pid 2>/dev/null
    do
        i=$(( (i+1) %4 ))
        printf "\r[${spin:$i:1}] " # Add text here, something like "Please be paitent..." maybe?
        sleep .1
    done
}

any_key() {
    local PROMPT="$1"
    read -r -p "$(printf "${Green}${PROMPT}${Color_Off}")" -n1 -s
    echo
}

## bash colors
# Reset
Color_Off='\e[0m'       # Text Reset

# Regular Colors
Black='\e[0;30m'        # Black
Red='\e[0;31m'          # Red
Green='\e[0;32m'        # Green
Yellow='\e[0;33m'       # Yellow
Blue='\e[0;34m'         # Blue
Purple='\e[0;35m'       # Purple
Cyan='\e[0;36m'         # Cyan
White='\e[0;37m'        # White

# Bold
BBlack='\e[1;30m'       # Black
BRed='\e[1;31m'         # Red
BGreen='\e[1;32m'       # Green
BYellow='\e[1;33m'      # Yellow
BBlue='\e[1;34m'        # Blue
BPurple='\e[1;35m'      # Purple
BCyan='\e[1;36m'        # Cyan
BWhite='\e[1;37m'       # White

# Underline
UBlack='\e[4;30m'       # Black
URed='\e[4;31m'         # Red
UGreen='\e[4;32m'       # Green
UYellow='\e[4;33m'      # Yellow
UBlue='\e[4;34m'        # Blue
UPurple='\e[4;35m'      # Purple
UCyan='\e[4;36m'        # Cyan
UWhite='\e[4;37m'       # White

# Background
On_Black='\e[40m'       # Black
On_Red='\e[41m'         # Red
On_Green='\e[42m'       # Green
On_Yellow='\e[43m'      # Yellow
On_Blue='\e[44m'        # Blue
On_Purple='\e[45m'      # Purple
On_Cyan='\e[46m'        # Cyan
On_White='\e[47m'       # White

# High Intensity
IBlack='\e[0;90m'       # Black
IRed='\e[0;91m'         # Red
IGreen='\e[0;92m'       # Green
IYellow='\e[0;93m'      # Yellow
IBlue='\e[0;94m'        # Blue
IPurple='\e[0;95m'      # Purple
ICyan='\e[0;96m'        # Cyan
IWhite='\e[0;97m'       # White

# Bold High Intensity
BIBlack='\e[1;90m'      # Black
BIRed='\e[1;91m'        # Red
BIGreen='\e[1;92m'      # Green
BIYellow='\e[1;93m'     # Yellow
BIBlue='\e[1;94m'       # Blue
BIPurple='\e[1;95m'     # Purple
BICyan='\e[1;96m'       # Cyan
BIWhite='\e[1;97m'      # White

# High Intensity backgrounds
On_IBlack='\e[0;100m'   # Black
On_IRed='\e[0;101m'     # Red
On_IGreen='\e[0;102m'   # Green
On_IYellow='\e[0;103m'  # Yellow
On_IBlue='\e[0;104m'    # Blue
On_IPurple='\e[0;105m'  # Purple
On_ICyan='\e[0;106m'    # Cyan
On_IWhite='\e[0;107m'   # White

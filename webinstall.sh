#!/bin/bash

# TekBase - Server Control Panel
# Copyright since 2005 TekLab
# Christian Frankenstein
# Website: teklab.de
#          teklab.net
# Email: service@teklab.de
# Discord: https://discord.gg/K49XAPv

# You can start webinstall.sh fully automatically with the command:
# ./webinstall.sh 2 1 1 2 "Debian" "9" "10000" "w2a384cj3d80smcz2x245ki49sg0i"

##############################
# Command Line Variables     #
##############################
# 1 = "german" otherwise "english"
langsel=$1

# 1 = Webserver + TekBASE + Teamspeak 3 + Dedicated installation
# 2 = Webserver + TekBASE + Dedicated installation
# 3 = Webserver + TekBASE"
# 4 = Webserver + Teamspeak 3 + Dedicated installation
# 5 = Webserver + Dedicated installation
# 6 = Webserver only Ioncube, Pecl SSH, Geoip, Qstat and FTP
# 7 = Semi-automatic web server installation with requests
# 8 = Teamspeak 3 + Dedicated installation
# 9 = Dedicated installation
modsel=$2

# 1 = No further yes/no queries
yessel=$3

# 1 = SuSE
# 2 = Debian / Ubuntu
# 3 = CentOS / Fedora / Red Hat
os_install=$4

# "CentOS", "Debian", "Fedora", "Red Hat", "SuSE", "Ubuntu"
os_name=$5

# Only the major version (e.g. 18 not 18.04)
os_version=$6

# 32 or 64Bit
os_typ=$(uname -m)

# If you are a reseller then enter your reseller ID and Key, otherwise this parameters are empty
# !currently not available!
# resellerid=$7
# resellerkey=$8

installhome=$(pwd)


##############################
# Colored Message            #
##############################
function color {
    if [ "$1" = "c" ]; then
        txt_color=6
    fi  
    if [ "$1" = "g" ]; then
        txt_color=2
    fi
    if [ "$1" = "r" ]; then
        txt_color=1
    fi
    if [ "$1" = "y" ]; then
        txt_color=3
    fi
    if [ "$2" = "n" ]; then
        echo -n "$(tput setaf $txt_color)$3"
    else
        echo "$(tput setaf $txt_color)$3"   
    fi
    tput sgr0
}


##############################
# Generate Password          #
##############################
function gen_passwd { 
    PWCHARS=$1
    [ "$PWCHARS" = "" ] && PWCHARS=16
    local password=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${PWCHARS} | xargs)
    echo "$password"
}


##############################
# Advanced Logging Function  #
##############################
function gen_logs {
    local input="$1"
    local log_type="$2"    # "cmd" or "msg" (defaults to "msg" if missing or invalid)
    local log_root="/home/tekbase/logs"
    local timestamp="[$(date +"%Y-%m-%d %H:%M:%S")]"
    local call_origin="$(caller 1)"

    # Ensure log directory exists
    mkdir -p "$log_root"

    local log_success_file="$log_root/installed.log"
    local log_error_file="$log_root/errors.log"

    # Expanded failure indicators
    local failure_keywords="fail|missing|not found|could not|error|warning|failed|unable|denied|unreachable|timed out|invalid|broken|no such file|exception"

    if [ "$log_type" = "cmd" ]; then
        local output
        output=$(eval "$input" 2>&1)
        local exit_code=$?

        if [ $exit_code -eq 0 ] && ! echo "$output" | grep -iE "$failure_keywords" >/dev/null; then
            {
                echo "$timestamp - ✅ Command succeeded: $input"
                echo "$timestamp - Output:"
                echo "$output"
                echo ""
            } | tee -a "$log_success_file"
        else
            {
                echo "$timestamp - ❌ Command failed: $input"
                echo "  ↳ Exit Code: $exit_code"
                echo "  ↳ Called from: $call_origin"
                echo "  ↳ Output:"
                echo "$output"
                echo ""
            } | tee -a "$log_error_file"
        fi
    else
        # Default to "msg" type
        if echo "$input" | grep -iE "$failure_keywords" >/dev/null; then
            echo "$timestamp - ⚠️ $input (from: $call_origin)" | tee -a "$log_error_file"
        else
            echo "$timestamp - $input" | tee -a "$log_success_file"
        fi
    fi
}
##############################
# Loading Spinner            #
##############################
function loading {
    SPINNER=("-" "\\" "|" "/")

    for sequence in $(seq 1 $1); do
        for I in "${SPINNER[@]}"; do
            echo -ne "\b$I"
            sleep 0.1
        done
    done
}


##############################
# Create Directory           #
##############################
function make_dir {
    if [ -n "$1" ] && [ ! -d "$1" ]; then
        mkdir -p "$1"
        gen_logs "Created directory: $1" msg
    else
        gen_logs "Directory already exists or path was empty: $1" msg
    fi
}


##############################
# Check Apache               #
##############################
function chk_apache {
    apache_inst=0
    if [ "$1" != "3" ]; then
        checka=$(which apache 2>&-)
        checkb=$(which apache2 2>&-)
        checkc=$(find /usr/include -name apache2)
        checkd=$(find /usr/include -name apache)
        if [ "$checka" != "" -o "$checkb" != "" -o "$checkc" != "" -o "$checkd" != "" ]; then
            apache_inst=1
            gen_logs "Apache (or variant) detected on Debian-based system." msg
        else
            gen_logs "Apache not found on Debian-based system." msg
        fi
    else
        checka=$(which httpd | grep -i "/httpd" 2>&-)
        if [ "$checka" != "" ]; then
            apache_inst=1
            gen_logs "Apache (httpd) detected on Red Hat-based system." msg
        else
            gen_logs "Apache (httpd) not found on Red Hat-based system." msg
        fi
    fi
}

##############################
# Check Netstat              #
##############################
function chk_netstat {
    netstat_inst=0
    check=$(which netstat 2>&-)
    if [ -n "$check" ]; then
        netstat_inst=1
        gen_logs "Netstat found at $check" msg
    else
        gen_logs "Netstat not found on system." msg
    fi
}

##############################
# Check OS                   #
##############################
function chk_os {
    os_install=""
    os_name=""
    os_version=""

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_name="$ID"  # e.g., ubuntu, debian, centos
        os_version="${VERSION_ID%%.*}"  # major version only

        case "$os_name" in
            ubuntu)
                os_install=2
                os_name="Ubuntu"
                ;;
            debian)
                os_install=2
                os_name="Debian"
                ;;
            centos)
                os_install=3
                os_name="CentOS"
                ;;
            rhel|redhat)
                os_install=3
                os_name="Red Hat"
                ;;
            fedora)
                os_install=3
                os_name="Fedora"
                ;;
            suse|sles|opensuse*)
                os_install=1
                os_name="SuSE"
                ;;
            *)
                os_install=""
                os_name="Unknown"
                ;;
        esac
        gen_logs "OS detected: $os_name $os_version (install type: $os_install)" msg
    else
        gen_logs "Unable to detect OS – /etc/os-release not found." msg
    fi
}

##############################
# Check MySQL                #
##############################
function chk_mysql {
    mysql_inst=0
    if [ "$1" != "3" ]; then
        checka=$(which mysql 2>&-)
    else
        checka=$(which mysql | grep -i "/mysql" 2>&-)
    fi
    if [ "$checka" != "" ]; then
        mysql_inst=1
        gen_logs "MySQL detected on system." msg
    else
        gen_logs "MySQL not found on system." msg
    fi
}


##############################
# Check PHP                  #
##############################
function chk_php {
    php_inst=0
    checka=$(php -m | grep -i "gd")
    if [ "$1" != "3" ]; then
        checkb=$(which php 2>&-)
    else
        checkb=$(which php | grep -i "/php" 2>&-)
    fi
    if [ "$checka" != "" -a "$checkb" != "" ]; then
        php_inst=1
        gen_logs "PHP and GD module found on system." msg
    else
        gen_logs "PHP or GD module not found." msg
    fi
}


##############################
# Check Web Panel            #
##############################
function chk_panel {
    web_panel="0"
    if [ -f /etc/init.d/psa ]; then
        web_panel="Plesk"
    elif [ -f /usr/local/vesta/bin/v-change-user-password ]; then
        web_panel="VestaCP"
    elif [ -d /var/www/froxlor ]; then
        web_panel="Froxlor"
    elif [ -d /etc/imscp ]; then
        web_panel="i-MSCP"
    elif [ -d /usr/local/ispconfig ]; then
        web_panel="ISPConfig"
    elif [ -d /var/cpanel ]; then
        web_panel="cPanel"
    elif [ -d /usr/local/directadmin ]; then
        web_panel="DirectAdmin"
    fi
    gen_logs "Detected web panel: $web_panel" msg
}


##############################
# Select Yes / No            #
##############################
function select_yesno {
    clear
    echo -e "$1"
    echo ""
    if [ "$langsel" = "1" ]; then
        echo "(1) Ja - Weiter"
        echo "(2) Nein - Beenden"
    else
        echo "(1) Yes - Continue"
        echo "(2) No - Exit"
    fi
    echo ""

    if [ "$langsel" = "1" ]; then
        if [ "$yesno" = "" ]; then
            echo -n "Bitte geben Sie ihre Auswahl an: "
        else
            color r n "Bitte geben Sie entweder 1 oder 2 ein: "
        fi
    else
        if [ "$yesno" = "" ]; then
            echo -n "Please enter your selection: "
        else
            color r n "Please enter either 1 or 2: "
        fi
    fi

    read -n 1 yesno

    for i in $yesno; do
    case "$i" in
        '1')
            clear
            gen_logs "User selected YES to continue." msg
        ;;
        '2')
            clear
            gen_logs "User selected NO to exit installer." msg
            exit 0
        ;;
        *)
            yesno=99
            clear
            gen_logs "Invalid input in select_yesno: $i" msg
            select_yesno "$1"
        ;;
    esac
    done
}


##############################
# Select Language            #
##############################
function select_lang {
    clear
    echo "TekBASE Webserver Installer"
    echo ""
    echo "(1) German"
    echo "(2) English"
    echo "(3) Exit"
    echo ""

    if [ "$langsel" = "" ]; then
        echo "Bitte waehlen Sie ihre Sprache."
        echo -n "Please select your language: "
    else
        color r x "Bitte geben Sie entweder 1,2 oder 3 ein!"
        color r n "Please enter only 1,2 or 3: "
    fi

    read -n 1 langsel

    for i in $langsel; do
    case "$i" in
        '1')
            clear
            gen_logs "Language selected: German" msg
        ;;
        '2')
            clear
            gen_logs "Language selected: English" msg
        ;;
        '3')
            clear
            gen_logs "User selected to exit during language selection." msg
            exit 0
        ;;
        *)
            langsel=99
            clear
            gen_logs "Invalid input in select_lang: $i" msg
            select_lang
        ;;
    esac
    done
}


##############################
# Select Mode                #
##############################
function select_mode {
    clear
    if [ "$langsel" = "1" ]; then
        echo "Installation Auswahl"
        echo ""
        echo "Waehlen Sie 1 oder 2. Dies ist perfekt fuer Anfaenger geeignet,"
        echo "welche nur einen Rootserver nutzen."
        echo ""
        echo "(1) Webserver + TekBASE + Teamspeak 3 + Rootserver Einrichtung"
        echo "(2) Webserver + TekBASE + Rootserver Einrichtung"
        echo "(3) Webserver + TekBASE"
        echo "(4) Webserver + Teamspeak 3 + Rootserver Einrichtung"
        echo "(5) Webserver + Rootserver Einrichtung"
        echo "(6) Webserver nur Ioncube, Pecl SSH, Geoip, Qstat und FTP"
        echo "(7) Semi-automatische Webserver Installation mit Abfrage"
        echo ""
        echo "(8) Teamspeak 3 + Rootserver Einrichtung"
        echo "(9) Rootserver Einrichtung"
        echo "(0) Exit"
    else
        echo "Installation selection"
        echo ""
        echo "Choose 1 or 2. This is perfect for beginners who use only one"
        echo "dedicated server."
        echo ""
        echo "(1) Webserver + TekBASE + Teamspeak 3 + Dedicated installation"
        echo "(2) Webserver + TekBASE + Dedicated installation"
        echo "(3) Webserver + TekBASE"
        echo "(4) Webserver + Teamspeak 3 + Dedicated installation"
        echo "(5) Webserver + Dedicated installation"
        echo "(6) Webserver only Ioncube, Pecl SSH, Geoip, Qstat and FTP"
        echo "(7) Semi-automatic web server installation with requests"
        echo ""
        echo "(8) Teamspeak 3 + Dedicated installation"
        echo "(9) Dedicated installation"
        echo "(0) Exit"
    fi
    echo ""

    if [ "$langsel" = "1" ]; then
        if [ "$modsel" = "" ]; then
            echo -n "Bitte geben Sie ihre Auswahl an: "
        else
            color r n "Bitte geben Sie entweder 1,2,3,4,5,6,7,8,9 oder 0 ein: "
        fi
    else
        if [ "$modsel" = "" ]; then
            echo -n "Please enter your selection: "
        else
            color r n "Please enter either 1,2,3,4,5,6,7,8,9 or 0: "
        fi
    fi

    read -n 1 modsel

    for i in $modsel; do
    case "$i" in
        '1')
            clear
            gen_logs "Mode selected: 1 (Full setup: Webserver + TekBASE + TS3 + Rootserver)" msg
        ;;
        '2')
            clear
            gen_logs "Mode selected: 2 (Webserver + TekBASE + Rootserver)" msg
        ;;
        '3')
            clear
            gen_logs "Mode selected: 3 (Webserver + TekBASE)" msg
        ;;
        '4')
            clear
            gen_logs "Mode selected: 4 (Webserver + TS3 + Rootserver)" msg
        ;;
        '5')
            clear
            gen_logs "Mode selected: 5 (Webserver + Rootserver)" msg
        ;;
        '6')
            clear
            gen_logs "Mode selected: 6 (Minimal Webserver setup)" msg
        ;;
        '7')
            clear
            gen_logs "Mode selected: 7 (Semi-automatic Webserver install)" msg
        ;;
        '8')
            clear
            gen_logs "Mode selected: 8 (TS3 + Rootserver)" msg
        ;;
        '9')
            clear
            gen_logs "Mode selected: 9 (Rootserver only)" msg
        ;;
        '0')
            clear
            gen_logs "User exited during mode selection." msg
            exit 0
        ;;
        *)
            modsel=99
            clear
            gen_logs "Invalid input in select_mode: $i" msg
            select_mode
        ;;
    esac
    done
}


##############################
# Select URL                 #
##############################
function select_url {
    clear
    [[ "$langsel" = "1" ]] && echo "Domains Auswahl" || echo "Domain selection"
    echo ""

    cd "$1" || { echo "Directory $1 not found!"; gen_logs "Directory $1 not found in select_url." msg; exit 1; }

    mapfile -t url_list < <(find . -maxdepth 1 -type d -printf '%f\n' | grep -E '^([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|([0-9]{1,3}\.){3}[0-9]{1,3})$')
    url_list=("${url_list[@]:0:9}")

    if [ "${#url_list[@]}" -eq 0 ]; then
        echo "No valid domains/IPs found."
        gen_logs "No valid domains or IP directories found in select_url." msg
        exit 1
    fi

    for i in "${!url_list[@]}"; do
        echo "($((i+1))) ${url_list[$i]}"
    done

    echo ""
    echo "(0) Exit"
    echo ""

    [[ "$langsel" = "1" ]] && prompt="Bitte geben Sie Ihre Auswahl an: " || prompt="Please enter your selection: "
    echo -n "$prompt"
    read -n 1 urlsel
    echo ""

    if [[ "$urlsel" =~ ^[1-9]$ ]] && (( urlsel <= ${#url_list[@]} )); then
        site_url="${url_list[$((urlsel-1))]}"
        gen_logs "User selected site directory: $site_url" msg
        clear
    elif [[ "$urlsel" == "0" ]]; then
        clear
        gen_logs "User exited during domain/IP selection." msg
        exit 0
    else
        clear
        gen_logs "Invalid input during select_url: $urlsel" msg
        echo "Invalid selection."
        select_url "$1"
    fi
}


##############################
# Select SSH Keys            #
##############################
function select_sshkeys {
    clear
    if [ "$langsel" = "1" ]; then
        echo "SSH Key Auswahl"
        echo ""
        echo "Sollen eigene SSH Keys generiert werden? Dies wird für den"
        echo "ersten beziehungsweise einzigen Server empfohlen."
        echo ""
        echo "(1) Ja"
        echo "(2) Nein"
        echo "(3) Exit"
    else
        echo "SSH Key selection"
        echo ""
        echo "Should own SSH keys be generated? This is recommended for the"
        echo "first or only server."
        echo ""
        echo "(1) Yes"
        echo "(2) No"
        echo "(3) Exit"
    fi
    echo ""

    if [ "$langsel" = "1" ]; then
        [ "$sshsel" = "" ] && echo -n "Bitte geben Sie ihre Auswahl an: " || color r n "Bitte geben Sie entweder 1,2 oder 3 ein: "
    else
        [ "$sshsel" = "" ] && echo -n "Please enter your selection: " || color r n "Please enter either 1,2 or 3: "
    fi

    read -n 1 sshsel

    for i in $sshsel; do
    case "$i" in
        '1')
            clear
            gen_logs "User selected to generate SSH keys." msg
        ;;
        '2')
            clear
            gen_logs "User selected not to generate SSH keys." msg
        ;;
        '3')
            clear
            gen_logs "User exited during SSH key selection." msg
            exit 0
        ;;
        *)
            sshsel=99
            clear
            gen_logs "Invalid input during SSH key selection: $i" msg
            select_sshkeys
        ;;
    esac
    done
}


##############################
# Choose Lang                #
##############################
if [ ! -n "$langsel" ]; then
    select_lang
fi

gen_logs "" ""


##############################
# Test OS                    #
##############################
if [ ! -n "$os_install" -a ! -n "$os_name" -a ! -n "$os_version" ]; then
    chk_os
fi

if [ ! -n "$os_install" -o ! -n "$os_name" -o ! -n "$os_version" ]; then
    clear
    if [ "$langsel" = "1" ]; then
        color r x "Es wird nur CentOS, Debian, Fedora, Red Hat, SuSE und Ubuntu unterstuetzt."
    else
        color r x "Only CentOS, Debian, Fedora, Red Hat, SuSE and Ubuntu are supported."
    fi
    gen_logs "Unsupported OS detected. Exiting. Detected values: $os_name $os_version ($os_install)" msg
    exit 0
fi

if [ ! -n "$yessel" ]; then
    yesno=""
    if [ "$langsel" = "1" ]; then
        select_yesno "Ihr System: $os_name $os_version - $os_typ. Ist dies korrekt?"
    else
        select_yesno "Your system: $os_name $os_version - $os_typ. Is this correct?"
    fi
    gen_logs "System: $os_name $os_version - $os_typ" msg
fi


##############################
# Test Root                  #
##############################
if [ "$(id -u)" != "0" ]; then
    su -
fi

if [ "$(id -u)" != "0" ]; then
    clear
    if [ "$langsel" = "1" ]; then
        color r x "Sie benoetigen root Rechte."
    else
        color r x "You need root privileges."
    fi
    gen_logs "You need root privileges. Install script was stopped." msg
    exit 0
else
    gen_logs "Root privileges confirmed." msg
fi


##############################
# Get IP, Hostname           #
##############################

local_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $NF; exit}')
host_name=$(hostname -f 2>/dev/null | awk '{print tolower($0)}')

if [ -z "$host_name" ]; then
    host_name=$(hostname | awk '{print tolower($0)}')
fi

if [ -z "$host_name" ]; then
    host_name="$local_ip"
fi

if ! grep -qE "127\.0\.1\.1\s+$host_name" /etc/hosts; then
    if ! [[ "$host_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Fixing /etc/hosts for hostname resolution: $host_name"
        echo "127.0.1.1   $host_name" >> /etc/hosts
        gen_logs "Hostname $host_name added to /etc/hosts for resolution." msg
    else
        gen_logs "Skipping /etc/hosts entry — host_name is an IP: $host_name" msg
    fi
fi


gen_logs "Hostname and IP - $host_name, $local_ip" msg


##############################
# Choose Mode                #
##############################
if [ ! -n "$modsel" ]; then
    select_mode
    gen_logs "Installation mode selected: $modsel" msg
fi

chk_netstat
gen_logs "Netstat check completed (status var: $netstat_inst)" msg

echo "" > /home/tekbase_status.txt
gen_logs "Status file initialized at /home/tekbase_status.txt" msg

##############################
# Install Libs And Progs     #
##############################
if [ ! -n "$yessel" ]; then
    yesno=""
    if [ "$langsel" = "1" ]; then
        gen_logs "Benutzer wird gefragt, ob Bibliotheken/Programme installiert werden sollen." msg
        select_yesno "Es wird jetzt autoconf, automake, build-essential, curl, expect, gcc, \ndmidecode, lm-sensors, m4, make, net-tools, openjdk, openssl-dev, patch, pwgen,\nscreen, smartmontools, sqlite, sudo, sysstat, unzip und wget installiert."
    else
        gen_logs "User is prompted to install required packages and libraries." msg
        select_yesno "Autoconf, automake, build-essential, curl, expect, gcc, dmidecode,\nlm-sensors, m4, make, net-tools, openjdk, openssl-dev, patch, pwgen, screen,\nsmartmontools, sqlite, sudo, sysstat, unzip and wget will now be installed."
    fi
fi

case "$os_install" in
    '1')  # SuSE
        clear
        gen_logs "Installing packages using Zypper (SuSE detected)." msg
        if [ "$modsel" != "7" ]; then
            chkyes="--non-interactive install"
            gen_logs "zypper --non-interactive update" cmd
        else
            chkyes="install"
            gen_logs "zypper update" cmd
        fi

        for i in autoconf automake m4 make screen sudo curl wget sqlite sqlite3 expect gcc \
                 libssh2-1-devel libopenssl-devel libmp3lame-devel libxml2-devel libxslt-devel \
                 libshout-devel libvorbis-devel dmidecode lm-sensors net-tools sysstat \
                 smartmontools patch pwgen unzip java-11-openjdk git; do
            gen_logs "zypper $chkyes $i" cmd
            gen_logs "-" "${i}"
        done

        gen_logs "zypper $chkyes -t pattern devel_basis" cmd
    ;;

    '2')  # Debian / Ubuntu
        clear
        gen_logs "Installing packages using apt-get (Debian/Ubuntu detected)." msg
        if [ "$modsel" != "7" ]; then
            chkyes="-y"
        else
            chkyes=""
        fi

        gen_logs "apt-get update && apt-get upgrade $chkyes" cmd

        for i in autoconf automake build-essential m4 make debconf-utils screen sudo curl wget \
                 sqlite3 expect gcc libssh2-1-dev libssl-dev libmp3lame-dev libxml2-dev \
                 libshout-dev libvorbis-dev dmidecode lm-sensors net-tools sysstat \
                 smartmontools patch pwgen unzip git; do
            gen_logs "apt-get install $i $chkyes" cmd
            gen_logs "-" "${i}"
        done

        gen_logs "Installing Java (openjdk-17-jre)" msg
        gen_logs "apt-get install openjdk-17-jre $chkyes" cmd

        gen_logs "Adding i386 architecture (if needed)" msg
        dpkg --add-architecture i386
        apt-get update

        gen_logs "Installing 32-bit libcurl for compatibility" msg
        apt-get install libcurl4-gnutls-dev:i386 $chkyes
    ;;

    '3')  # CentOS / Red Hat / Fedora
        clear
        gen_logs "Installing packages using yum/dnf (RedHat-based OS detected)." msg
        if command -v dnf >/dev/null 2>&1; then
            pkgmgr="dnf"
        else
            pkgmgr="yum"
        fi

        if [ "$modsel" != "7" ]; then
            chkyes="-y"
        else
            chkyes=""
        fi

        gen_logs "$pkgmgr update $chkyes" cmd

        gen_logs "Installing epel-release" msg
        $pkgmgr install epel-release -y

        gen_logs "Getting repo list" msg
        $pkgmgr repolist

        for i in autoconf automake m4 make screen sudo curl wget sqlite expect gcc openssl-devel \
                 dmidecode lm-sensors net-tools sysstat smartmontools patch pwgen unzip \
                 java-11-openjdk git; do
            gen_logs "$pkgmgr install $i $chkyes" cmd
            gen_logs "-" "${i}"
        done

        gen_logs "$pkgmgr groupinstall 'Development Tools' $chkyes" cmd
    ;;
esac

# Enable sensors (optional - may prompt user)
gen_logs "yes | sensors-detect --auto" cmd

##############################
# Install Apache, PHP, MySQL #
##############################
if [[ "$modsel" -lt 8 ]]; then

    # --- Apache Installation ---
    chk_apache "$os_install"

    if [[ "$apache_inst" == "0" ]]; then
        gen_logs "Apache not detected. Proceeding with installation." msg
        if [[ -z "$yessel" ]]; then
            yesno=""
            if [[ "$langsel" == "1" ]]; then
                select_yesno "Apache Webserver nicht gefunden. Dieser wird jetzt installiert."
            else
                select_yesno "Apache web server not found. This will now be installed."
            fi
        fi

        case "$os_install" in
            "1")  # openSUSE
                gen_logs "zypper --non-interactive install apache2" cmd || exit 1
                systemctl enable apache2
                systemctl restart apache2
                ;;
            "2")  # Debian/Ubuntu
                export DEBIAN_FRONTEND=noninteractive
                gen_logs "apt-get install -y apache2" cmd || exit 1
                systemctl enable apache2
                systemctl restart apache2
                ;;
            "3")  # RHEL/CentOS
                gen_logs "yum install -y httpd" cmd || exit 1
                systemctl enable httpd
                systemctl restart httpd
                ;;
        esac

        chk_apache "$os_install"
        if [[ "$apache_inst" == "0" ]]; then
            clear
            echo "[ERROR] Apache installation failed. Please install manually."
            echo "Check apache: error" >> /home/tekbase_status.txt
            gen_logs "*** Apache could not be installed." msg
            exit 1
        fi

        echo "Check apache: ok" >> /home/tekbase_status.txt
        gen_logs "*** Apache installed successfully." msg
    else
        echo "Check apache: ok" >> /home/tekbase_status.txt
        gen_logs "Apache already installed." msg
    fi

    # --- PHP Installation ---
    if [[ -z "$yessel" ]]; then
        if [[ "$langsel" == "1" ]]; then
            select_yesno "Es wird jetzt PHP 8.4 und notwendige Erweiterungen installiert."
        else
            select_yesno "PHP 8.4 and necessary extensions will now be installed."
        fi
    fi

    gen_logs "[INFO] Installing PHP 8.4 and necessary modules..." msg

    case "$os_install" in
        "1") # openSUSE
            gen_logs "zypper refresh" cmd
            if zypper search php8.4 &>/dev/null; then
                packages="apache2-mod-php8.4 php8.4 php8.4-common php8.4-cli php8.4-curl php8.4-devel php8.4-gd php8.4-mbstring php8.4-mysql php8.4-ssh2 php8.4-xml php8.4-zip php8.4-intl"
            else
                gen_logs "[WARNING] PHP 8.4 is not available in openSUSE. Using default PHP 8 packages." msg
                packages="apache2-mod-php8 php8 php8-common php8-cli php8-curl php8-devel php8-gd php8-mbstring php8-mysql php8-ssh2 php8-xml php8-zip php8-intl"
            fi
            gen_logs "zypper install -y $packages" cmd || { gen_logs "[ERROR] PHP installation failed!"; exit 1; }
            ;;

        "2") # Debian/Ubuntu
            export DEBIAN_FRONTEND=noninteractive
            gen_logs "apt-get update -y" cmd
            gen_logs "apt-get install -y software-properties-common" cmd
            gen_logs "add-apt-repository -y ppa:ondrej/php" cmd
            gen_logs "apt-get update -y" cmd

            if apt-cache show php8.4 &>/dev/null; then
                PHPV="8.4"
            else
                gen_logs "[WARNING] PHP 8.4 is not available in PPA. Installing PHP 8.3 instead." msg
                PHPV="8.3"
            fi

            packages="libapache2-mod-php$PHPV php$PHPV php$PHPV-common php$PHPV-cli php$PHPV-curl php$PHPV-dev php$PHPV-gd php$PHPV-mbstring php$PHPV-mysql php$PHPV-ssh2 php$PHPV-xml php$PHPV-zip php$PHPV-intl"

            gen_logs "apt-get install -y $packages" cmd || { gen_logs "[ERROR] PHP installation failed!"; exit 1; }
            ;;

        "3") # RHEL/CentOS
            gen_logs "yum install -y epel-release yum-utils" cmd
            gen_logs "yum install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm" cmd

            if yum list available | grep -q remi-php84; then
                gen_logs "yum-config-manager --enable remi-php84" cmd
                PHPV="8.4"
            else
                gen_logs "[WARNING] PHP 8.4 not available in Remi repo. Installing PHP 8.3 instead." msg
                gen_logs "yum-config-manager --enable remi-php83" cmd
                PHPV="8.3"
            fi

            packages="php php-common php-cli php-curl php-devel php-gd php-mbstring php-mysqlnd php-pecl-ssh2 php-xml php-pecl-zip php-intl"

            gen_logs "yum install -y $packages" cmd || { gen_logs "[ERROR] PHP installation failed!"; exit 1; }
            ;;
    esac

    chk_php "$os_install"
    if [[ "$php_inst" == "0" ]]; then
        clear
        if [[ "$langsel" == "1" ]]; then
            color r x "PHP und die Erweiterungen konnten nicht vollständig installiert werden."
            color r x "Bitte nehmen Sie die Installation manuell vor."
        else
            color r x "PHP and its extensions could not be completely installed."
            color r x "Please complete the installation manually."
        fi
        echo "Check php: error" >> /home/tekbase_status.txt
        gen_logs "*** PHP 8.4 installation verification failed." msg
        exit 1
    fi

    echo "Check php: ok" >> /home/tekbase_status.txt
    gen_logs "*** PHP 8.4 successfully installed." msg

    # --- Install MySQL/MariaDB ---
    chk_mysql $os_install

    if [ "$mysql_inst" = "0" ]; then
        gen_logs "MySQL/MariaDB not found. Proceeding with installation." msg
        [ -z "$yessel" ] && {
            yesno=""
            [ "$langsel" = "1" ] && \
                select_yesno "MySQL/MariaDB Server wird installiert." || \
                select_yesno "MySQL/MariaDB server will be installed."
        }

        mysqlpwd=$(gen_passwd 12)
        echo "MySQL root password: $mysqlpwd" > /home/tekbase_mysql.txt
        gen_logs "Generated MySQL root password stored in /home/tekbase_mysql.txt" msg

        case "$os_install" in
            "1") # openSUSE
                gen_logs "zypper --non-interactive install mariadb mariadb-tools" cmd
                systemctl enable --now mariadb
                ;;
            "2") # Debian/Ubuntu
                export DEBIAN_FRONTEND=noninteractive
                debconf-set-selections <<< "mariadb-server mariadb-server/root_password password $mysqlpwd"
                debconf-set-selections <<< "mariadb-server mariadb-server/root_password_again password $mysqlpwd"
                gen_logs "apt-get install mariadb-server -y" cmd
                sleep 5
                if mysqladmin ping >/dev/null 2>&1; then
                    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysqlpwd';"
                    gen_logs "MySQL root password set via ALTER USER" msg
                else
                    gen_logs "MySQL server not responding to set root password" msg
                fi
                systemctl enable --now mariadb
                ;;
            "3") # RHEL/Fedora
                pkgmgr=$(command -v dnf || echo yum)
                gen_logs "$pkgmgr install mariadb-server mariadb -y" cmd
                systemctl enable --now mariadb
                ;;
        esac

        chk_mysql $os_install
        if [ "$mysql_inst" = "0" ]; then
            color r x "MySQL/MariaDB could not be installed. Please install manually."
            gen_logs "MySQL/MariaDB installation failed." msg
            echo "Check mysql: error" >> /home/tekbase_status.txt
            exit 1
        fi
        echo "Check mysql: ok" >> /home/tekbase_status.txt
        gen_logs "MySQL/MariaDB successfully installed." msg
    else
        echo "Check mysql: ok" >> /home/tekbase_status.txt
        gen_logs "MySQL/MariaDB already installed." msg
    fi

fi

##############################
# Check PHP Version And Paths #
##############################
if [ "$modsel" -lt 8 ]; then
    if systemctl list-units --type=service | grep -q apache2; then
        systemctl restart apache2
        gen_logs "Restarted apache2 service." msg
    elif systemctl list-units --type=service | grep -q httpd; then
        systemctl restart httpd
        gen_logs "Restarted httpd service." msg
    fi

    php_ioncube=$(php -m | grep -i "ioncube")
    php_ssh=$(php -m | grep -i "ssh2")

    php_version=$(php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;")
    php_inidir=$(php -r "echo PHP_CONFIG_FILE_PATH;")
    php_extdir=$(php -r "echo PHP_EXTENSION_DIR;")
    php_exinidir=$(php -r "echo PHP_CONFIG_FILE_SCAN_DIR;")
    php_dir=$(dirname "$php_inidir")

    php_apachedir=""
    php_fpmdir=""

    if [ -f "$php_dir/apache2/php.ini" ]; then
        php_apachedir="$php_dir/apache2"
    fi
    if [ -f "$php_dir/fpm/php.ini" ]; then
        php_fpmdir="$php_dir/fpm"
    fi

    if systemctl list-units --type=service | grep -q "php${php_version/./}-fpm"; then
        systemctl restart "php${php_version/./}-fpm"
        gen_logs "Restarted php${php_version/./}-fpm service." msg
    elif systemctl list-units --type=service | grep -q php-fpm; then
        systemctl restart php-fpm
        gen_logs "Restarted php-fpm service." msg
    fi

    gen_logs "Detected PHP $php_version, INI: $php_inidir, EXT: $php_extdir, SCAN: $php_exinidir" msg
fi

##############################
# Install Pecl SSH2, Ioncube #
##############################
if [ "$modsel" -lt 8 ]; then
    if [ "$php_ssh" = "" ]; then
        cd "$installhome"

        if [ ! -f libssh2-1.9.0.tar.gz ]; then
            wget --no-check-certificate https://www.libssh2.org/download/libssh2-1.9.0.tar.gz
        fi
        tar -xzf libssh2-1.9.0.tar.gz
        cd libssh2-1.9.0
        export OPENSSL_CONF=/etc/ssl/openssl.cnf
        ./configure --prefix=/usr --with-openssl --with-libssl-prefix=/usr && make -j$(nproc) && make install
        cd ..
        rm -rf libssh2-1.9.0 libssh2-1.9.0.tar.gz
        gen_logs "Compiled and installed libssh2." msg

        if [[ "$php_version" == "5.6" || "$php_version" == "7.0" ]]; then
            ssh2_pkg="ssh2-0.13"
        else
            ssh2_pkg="ssh2-1.3.1"
        fi

        if [ ! -f "$ssh2_pkg.tgz" ]; then
            wget --no-check-certificate "https://pecl.php.net/get/$ssh2_pkg.tgz"
        fi

        tar -xzf "$ssh2_pkg.tgz"
        cd "$ssh2_pkg"
        phpize && ./configure --with-ssh2 && make -j$(nproc) && make install
        cd ..
        rm -rf "$ssh2_pkg" "$ssh2_pkg.tgz"
        gen_logs "Compiled and installed SSH2 extension." msg

        echo "extension=ssh2.so" > "$php_exinidir/20-ssh2.ini"
        if [ "$os_install" = "1" ] || [ "$os_install" = "2" ]; then
            [ -d "$php_apachedir/conf.d" ] && echo "extension=ssh2.so" > "$php_apachedir/conf.d/20-ssh2.ini"
            [ -d "$php_fpmdir/conf.d" ] && echo "extension=ssh2.so" > "$php_fpmdir/conf.d/20-ssh2.ini"
        fi

        php_ssh=$(php -m | grep -i "ssh2")
        if [ "$php_ssh" = "" ]; then
            clear
            echo "Check ssh2: error" >> /home/tekbase_status.txt
            gen_logs "SSH2 PHP extension failed to install." msg
            exit 1
        else
            echo "Check ssh2: ok" >> /home/tekbase_status.txt
            gen_logs "SSH2 PHP extension installed successfully." msg
        fi
    else
        echo "Check ssh2: ok" >> /home/tekbase_status.txt
        gen_logs "SSH2 PHP extension already installed." msg
    fi

    sed -i '/^HostKeyAlgorithms*/d' /etc/ssh/sshd_config
    sed -i '/^PubkeyAcceptedKeyTypes*/d' /etc/ssh/sshd_config
    echo "HostKeyAlgorithms ssh-rsa,ssh-dss" >> /etc/ssh/sshd_config
    echo "PubkeyAcceptedKeyTypes ssh-rsa,ssh-dss" >> /etc/ssh/sshd_config
    gen_logs "Updated SSH config to support older key algorithms." msg

    if [ "$php_ioncube" = "" ]; then
        cd /usr/local
        [ -d ioncube ] && rm ioncube

        if [ "$os_typ" = "x86_64" ]; then
            wget --no-check-certificate https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz
            tar xvfz ioncube_loaders_lin_x86-64.tar.gz
        else
            wget --no-check-certificate https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86.tar.gz
            tar xvfz ioncube_loaders_lin_x86.tar.gz
        fi

        if [ ! -d ioncube ]; then
            cd $installhome
            mv ioncube_x86-64.tar.gz /usr/local
            mv ioncube_x86.tar.gz /usr/local
            cd /usr/local
            [ "$os_typ" = "x86_64" ] && tar -xzf ioncube_x86-64.tar.gz || tar -xzf ioncube_x86.tar.gz
            rm ioncube_x86*.tar.gz
        fi

        cd ioncube
        cp *.* $php_extdir

        cd $php_exinidir
        echo "zend_extension=ioncube_loader_lin_$php_version.so" > 00-ioncube.ini
        if [ "$os_install" = "1" -o "$os_install" = "2" ]; then
            [ -d $php_apachedir/conf.d ] && echo "zend_extension=$php_extdir/ioncube_loader_lin_$php_version.so" > $php_apachedir/conf.d/00-ioncube.ini
            [ -d $php_fpmdir/conf.d ] && echo "zend_extension=$php_extdir/ioncube_loader_lin_$php_version.so" > $php_fpmdir/conf.d/00-ioncube.ini
        fi

        php_ioncube=$(php -m | grep -i "ioncube")
        if [ "$php_ioncube" = "" ]; then
            clear
            echo "Check ioncube: error" >> /home/tekbase_status.txt
            gen_logs "Ioncube extension failed to install." msg
            exit 0
        else
            echo "Check ioncube: ok" >> /home/tekbase_status.txt
            gen_logs "Ioncube extension installed successfully." msg
        fi
    else
        echo "Check ioncube: ok" >> /home/tekbase_status.txt
        gen_logs "Ioncube extension already installed." msg
    fi
fi

##############################
# Configure Php              #
##############################
if [ $modsel -lt 8 ]; then
    for ini in "$php_inidir/php.ini" "$php_apachedir/php.ini" "$php_fpmdir/php.ini"; do
        if [ -f "$ini" ]; then
            sed -i '/allow_url_fopen/c\allow_url_fopen=on' "$ini"
            sed -i '/max_execution_time/c\max_execution_time=360' "$ini"
            sed -i '/max_input_time/c\max_input_time=1000' "$ini"
            sed -i '/memory_limit/c\memory_limit=128M' "$ini"
            sed -i '/post_max_size/c\post_max_size=32M' "$ini"
            sed -i '/upload_max_filesize/c\upload_max_filesize=32M' "$ini"
            echo "date.timezone=\"Europe/Berlin\"" >> "$ini"
            gen_logs "Updated PHP settings in $ini" msg
        fi
    done

    [ -f /etc/apache2/confixx_vhosts/web0.conf ] && \
        sed -i '/allow_url_fopen/c\php_admin_flag allow_url_fopen on' /etc/apache2/confixx_vhosts/web0.conf && \
        gen_logs "Updated allow_url_fopen in confixx_vhosts/web0.conf" msg

    [ -f /etc/apache2/confixx_mhost.conf ] && \
        sed -i '/allow_url_fopen/c\php_admin_flag allow_url_fopen on' /etc/apache2/confixx_mhost.conf && \
        gen_logs "Updated allow_url_fopen in confixx_mhost.conf" msg
fi


##############################
# Restart Apache And PHP     #
##############################
if [ "$modsel" -lt 8 ]; then
    if [ "$os_install" != "3" ]; then
        # Restart Apache
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart apache2
            gen_logs "Apache2 restarted using systemctl" ""
        else
            service apache2 restart
            gen_logs "Apache2 restarted using service" ""
        fi

        # Restart PHP-FPM (if installed)
        if systemctl list-units --type=service | grep -q "php${php_version}-fpm"; then
            systemctl restart php${php_version}-fpm
            gen_logs "PHP-FPM restarted using systemctl" ""
        elif service "php${php_version}-fpm" status >/dev/null 2>&1; then
            service php${php_version}-fpm restart
            gen_logs "PHP-FPM restarted using service" ""
        fi
    else
        # RHEL/CentOS/Fedora - Apache is httpd
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart httpd
            gen_logs "httpd restarted using systemctl (RHEL/CentOS)" ""
        else
            service httpd restart
            gen_logs "httpd restarted using service (RHEL/CentOS)" ""
        fi
    fi
fi

##############################
# Mail Check                 #
##############################
if [ $modsel -lt 8 ]; then
    if [ "$netstat_inst" = "1" ]; then
        check=$(netstat -tlpn | grep ":25 ")
    else
        check=$(ss -tlpn | grep ":25 ")
    fi
    if [ "$check" = "" ]; then
        check=$(which postfix 2>&-)
        if [ "$check" = "" ]; then
            if [ ! -n "$yessel" ]; then
                yesno=""
                if [ "$langsel" = "1" ]; then
                    select_yesno "Postfix wurde nicht gefunden. Dieser wird jetzt installiert."
                else
                    select_yesno "Postfix not found. This will now be installed."
                fi
            fi
            for i in $os_install; do
    	    case "$i" in
    	        '1')
    	            clear
    	            if [ "$modsel" != "7" ]; then
    	                zypper --non-interactive install postfix
                        gen_logs "Installed postfix using zypper (non-interactive)" "postfix"
    	            else
     	                zypper install postfix
                        gen_logs "Installed postfix using zypper" "postfix"
    	            fi
    	        ;;
    	        '2')
    	            clear
            	    if [ "$modsel" != "7" ]; then
            	        export DEBIAN_FRONTEND=noninteractive
            	        debconf-set-selections <<< "postfix postfix/mailname string $host_name"
            	        debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
            	        apt-get install postfix -y
                        gen_logs "Installed postfix using apt-get -y" "postfix"
            	    else
            	        apt-get install postfix
                        gen_logs "Installed postfix using apt-get" "postfix"
            	    fi
    	        ;;
    	        '3')
            	    clear
            	    if [ "$modsel" != "7" ]; then
            	        yum install postfix -y
                        gen_logs "Installed postfix using yum -y" "postfix"
            	    else
            	        yum install postfix
                        gen_logs "Installed postfix using yum" "postfix"
            	    fi
    	        ;;
    	    esac
    	    done
        fi
    fi
fi

##############################
# Install Qstat              #
##############################
if [ "$os_install" = "2" ]; then
    apt-get install qstat
    gen_logs "Installed qstat from apt" "qstat"
    if [ -f /usr/bin/qstat ]; then
        chmod 0755 /usr/bin/qstat
        cp /usr/bin/qstat /
        gen_logs "Copied qstat to /" "qstat"
    fi
    if [ ! -f /usr/bin/qstat -a -f /usr/bin/quakestat ]; then
        chmod 0755 /usr/bin/quakestat
        cp /usr/bin/quakestat /usr/bin/qstat
        cp /usr/bin/qstat /
        gen_logs "Fallback to quakestat as qstat" "qstat"
    fi
fi

if [ ! -f /qstat ]; then
    cd $installhome
    if [ ! -f qstat.tar.gz ]; then
        wget --no-check-certificate https://teklab.s3.amazonaws.com/tekbase_qstat.tar.gz
        gen_logs "Downloaded qstat package" ""
        tar -xzf tekbase_qstat.tar.gz
        rm tekbase_qstat.tar.gz
    else
        tar -xzf qstat.tar.gz
        rm qstat.tar.gz
    fi

    cd qstat
    ./configure && make all install
    gen_logs "Compiled and installed qstat" "qstat"
    chmod 0755 qstat
    cp qstat /usr/bin
    cp qstat /

    if [ -d /var/www/empty ]; then cp qstat /var/www/empty; fi
    if [ -d /srv/www/empty ]; then cp qstat /srv/www/empty; fi
    if [ -d /home/www/empty ]; then cp qstat /home/www/empty; fi

    cd $installhome
    rm -r qstat

    if [ ! -f /qstat ]; then
        echo "Check qstat: error" >> /home/tekbase_status.txt
        gen_logs "Qstat binary not found after install" "qstat"
    else
        echo "Check qstat: ok" >> /home/tekbase_status.txt
        gen_logs "Qstat installed successfully" "qstat"
    fi
else
    echo "Check qstat: ok" >> /home/tekbase_status.txt
    gen_logs "Qstat already exists, skipping" "qstat"
fi


##############################
# Install Scripts            #
##############################
if [ "$modsel" = "1" ] || [ "$modsel" = "2" ] || [ "$modsel" = "4" ] || [ "$modsel" = "5" ] || [ "$modsel" = "8" ] || [ "$modsel" = "9" ]; then
    if [ ! -f skripte.tar ]; then
        cd /home
        git clone https://github.com/teklab-de/tekbase-scripts-linux.git skripte
        gen_logs "Cloned tekbase-scripts-linux.git into /home/skripte" ""
        if [ ! -f /home/skripte/autoupdater ]; then
            cd $installhome
            wget --no-check-certificate https://teklab.s3.amazonaws.com/tekbase_scripts.tar
            tar -xzf tekbase_scripts.tar -C /home
            rm tekbase_scripts.tar
            gen_logs "Downloaded and extracted tekbase_scripts.tar" ""
        fi
        cd skripte
        mkdir cache
        chmod 755 *
        chmod 777 cache
        gen_logs "Prepared skripte folder with permissions and cache/" ""
        cd $installhome
    else
        tar -xzf skripte.tar -C /home
        rm skripte.tar
        gen_logs "Extracted skripte.tar to /home" ""
    fi

    if [ ! -f hlstats.tar ]; then
        wget --no-check-certificate https://teklab.s3.amazonaws.com/tekbase_hlstats.tar
        tar -xzf tekbase_hlstats.tar -C /home/skripte
        rm tekbase_hlstats.tar
        gen_logs "Downloaded and extracted tekbase_hlstats.tar" ""
    else
        tar -xzf hlstats.tar -C /home/skripte
        rm hlstats.tar
        gen_logs "Extracted hlstats.tar to /home/skripte" ""
    fi

    userpwd=$(gen_passwd 8)
    useradd -g users -p $(perl -e 'print crypt("'$userpwd'","Sa")') -s /bin/bash -m user-webi -d /home/user-webi
    gen_logs "Created user-webi with generated password" ""

    cd $installhome
    if [ ! -f user-webi.tar ]; then
        wget --no-check-certificate https://teklab.s3.amazonaws.com/tekbase_user-webi.tar
        tar -xzf tekbase_user-webi.tar -C /home
        rm tekbase_user-webi.tar
        gen_logs "Downloaded and extracted tekbase_user-webi.tar" ""
    else
        tar -xzf user-webi.tar -C /home
        rm user-webi.tar
        gen_logs "Extracted user-webi.tar to /home" ""
    fi

    if [ ! -f keys.tar ]; then
        wget --no-check-certificate https://teklab.s3.amazonaws.com/tekbase_keys.tar
        tar -xzf tekbase_keys.tar -C /home/user-webi
        rm tekbase_keys.tar
        gen_logs "Downloaded and extracted tekbase_keys.tar to /home/user-webi" ""
    else
        tar -xzf keys.tar -C /home/user-webi
        rm keys.tar
        gen_logs "Extracted keys.tar to /home/user-webi" ""
    fi

    if [ -d /home/skripte ]; then
        echo "Check scripts: ok" >> /home/tekbase_status.txt
        gen_logs "Script installation completed successfully." ""
    else
        echo "Check scripts: error" >> /home/tekbase_status.txt
        gen_logs "Script installation failed: /home/skripte not found." ""
    fi
fi


##############################
# Configure Sudo (Safe Way) #
##############################
if [[ "$modsel" =~ ^(1|2|4|5|8|9)$ ]]; then
    if [ "$os_install" = "3" ]; then
        cp /etc/sudoers /etc/sudoers.tekbase
        echo "root ALL=(ALL:ALL) ALL" > /etc/sudoers
        chmod 0440 /etc/sudoers
        gen_logs "Reset sudoers for CentOS/RHEL safely." ""
    fi

    rm -f /etc/sudoers.d/user-webi

    cat <<EOF > /etc/sudoers.d/user-webi
user-webi ALL=(ALL) NOPASSWD: /home/skripte/tekbase, /usr/bin/useradd, /usr/bin/usermod, /usr/bin/userdel
EOF

    chmod 0440 /etc/sudoers.d/user-webi
    gen_logs "Configured /etc/sudoers.d/user-webi with proper permissions." ""
fi


##############################
# Check Sudo                 #
##############################
if [ "$modsel" = "1" ] || [ "$modsel" = "2" ] || [ "$modsel" = "4" ] || [ "$modsel" = "5" ] || [ "$modsel" = "8" ] || [ "$modsel" = "9" ]; then
    cd /home/skripte
    sudochk=$(su user-webi -c "sudo ./tekbase 1 tekbasewi testpw")
    cd ..
    if [ "$sudochk" = "ID1" ]; then
        echo "Check sudo: ok" >> /home/tekbase_status.txt
        userdel tekbasewi
        rm -r /home/tekbasewi
        gen_logs "Sudo test passed — user-webi can run tekbase as root." ""
    else
        echo "Check sudo: error" >> /home/tekbase_status.txt
        gen_logs "Sudo test failed — user-webi could not execute tekbase." ""
    fi
fi


##############################
# Install and Configure FTP  #
##############################

install_ftp="1"
if [ -f /etc/proftpd.tekbase ] || [ -f /etc/proftpd.conf ] || [ -f /etc/proftpd/proftpd.conf ] || [ -f /etc/vsftpd.conf ]; then
    install_ftp="0"
fi

if [ "$install_ftp" = "1" ]; then
    if [ "$os_install" = "1" ]; then
        pkg_install="zypper"
        pkg_opts="--non-interactive install"
    elif [ "$os_install" = "2" ]; then
        pkg_install="apt-get"
        pkg_opts="-y install"
        export DEBIAN_FRONTEND=noninteractive
    elif [ "$os_install" = "3" ]; then
        pkg_install="yum"
        pkg_opts="-y install"
    fi

    gen_logs "$pkg_install $pkg_opts vsftpd" cmd
fi

##############################
# Configure FTP              #
##############################
if [ -f /etc/vsftpd.conf ]; then
    cp /etc/vsftpd.conf /etc/vsftpd.tekbase

    sed -i '/write_enable/c\write_enable=YES' /etc/vsftpd.conf
    sed -i '/chroot_local_user/c\chroot_local_user=YES' /etc/vsftpd.conf
    sed -i '/userlist_enable/c\userlist_enable=NO' /etc/vsftpd.conf

    if command -v systemctl >/dev/null; then
        systemctl restart vsftpd
    else
        service vsftpd restart
    fi

    if [ $? -eq 0 ]; then
        echo "Check vsftpd: ok" >> /home/tekbase_status.txt
        gen_logs "vsftpd configured and restarted successfully" msg
    else
        echo "Check vsftpd: error" >> /home/tekbase_status.txt
        gen_logs "vsftpd restart failed" msg
    fi
else
    echo "Check vsftpd: error" >> /home/tekbase_status.txt
    gen_logs "vsftpd installation failed (config not found)" msg
fi

##############################
# Check and Remove ProFTPD   #
##############################
if [ -f /etc/proftpd.conf ] || [ -f /etc/proftpd/proftpd.conf ]; then
    gen_logs "ProFTPD installation detected — removing." msg

    if [ "$os_install" = "1" ]; then
        zypper remove -y proftpd
        gen_logs "Removed proftpd (zypper)" msg
    elif [ "$os_install" = "2" ]; then
        apt-get remove --purge -y proftpd
        gen_logs "Removed proftpd (apt-get)" msg
    elif [ "$os_install" = "3" ]; then
        yum remove -y proftpd
        gen_logs "Removed proftpd (yum)" msg
    fi

    echo "Check proftpd: removed" >> /home/tekbase_status.txt
fi
##############################
# Configure TS3 Firewall     #
##############################
function configure_ts3_firewall {
    local ts3_ports_udp=(9987)
    local ts3_ports_tcp=(10011 30033)
    local firewall_set=0

    gen_logs "Configuring firewall for TeamSpeak 3" msg

    if command -v ufw >/dev/null 2>&1; then
        firewall_set=1
        for port in "${ts3_ports_udp[@]}"; do
            gen_logs "ufw allow $port/udp" cmd
        done
        for port in "${ts3_ports_tcp[@]}"; do
            gen_logs "ufw allow $port/tcp" cmd
        done
        gen_logs "Opened TS3 ports using ufw" msg

    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall_set=1
        for port in "${ts3_ports_udp[@]}"; do
            gen_logs "firewall-cmd --permanent --add-port=$port/udp" cmd
        done
        for port in "${ts3_ports_tcp[@]}"; do
            gen_logs "firewall-cmd --permanent --add-port=$port/tcp" cmd
        done
        gen_logs "firewall-cmd --reload" cmd
        gen_logs "Opened TS3 ports using firewalld" msg

    elif command -v iptables >/dev/null 2>&1; then
        firewall_set=1
        for port in "${ts3_ports_udp[@]}"; do
          if ! iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null; then
              gen_logs "iptables -A INPUT -p udp --dport $port -j ACCEPT" cmd
          fi
        done
        for port in "${ts3_ports_tcp[@]}"; do
            iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || gen_logs "iptables -A INPUT -p tcp --dport $port -j ACCEPT" cmd
        done
        gen_logs "Opened TS3 ports using iptables" msg
    fi

    if [ "$firewall_set" -eq 0 ]; then
        gen_logs "No firewall found. Attempting to install iptables..." msg
        case "$os_install" in
            1) gen_logs "zypper --non-interactive install iptables" cmd ;;
            2) gen_logs "apt-get install -y iptables" cmd ;;
            3) gen_logs "yum install -y iptables" cmd ;;
        esac

        if command -v iptables >/dev/null 2>&1; then
            gen_logs "iptables installed successfully" msg
            configure_ts3_firewall
        else
            gen_logs "Failed to install iptables firewall" msg
        fi
    fi
}

##############################
# Install Teamspeak 3        #
##############################
if [ "$modsel" = "1" ] || [ "$modsel" = "4" ] || [ "$modsel" = "8" ]; then
    cd "$installhome"
    adminpwd=$(gen_passwd 8)

    pkill -u user-webi ts3server 2>/dev/null || true

    if [ -d /home/user-webi/teamspeak3 ]; then
        mv /home/user-webi/teamspeak3 /home/user-webi/teamspeak3_backup
        gen_logs "Backed up old TeamSpeak install" msg
    fi

    ts_arch=$( [ "$os_typ" = "x86_64" ] && echo "amd64" || echo "x86" )
    fixed_ts_version="3.13.7"
    ts_file="teamspeak3-server_linux_${ts_arch}-${fixed_ts_version}.tar.bz2"
    ts_url="https://files.teamspeak-services.com/releases/server/${fixed_ts_version}/${ts_file}"

    if command -v curl >/dev/null; then
        gen_logs "curl -O $ts_url" cmd
    elif command -v wget >/dev/null; then
        gen_logs "wget $ts_url" cmd
    else
        gen_logs "curl or wget not found — cannot download TeamSpeak" msg
        exit 1
    fi

    gen_logs "tar -xjf $ts_file" cmd
    rm -f "$ts_file"
    mv "teamspeak3-server_linux_${ts_arch}" /home/user-webi/teamspeak3
    chown -R user-webi:users /home/user-webi/teamspeak3

    cd /home/user-webi/teamspeak3
    su user-webi -c "touch .ts3server_license_accepted"

    su user-webi -c "./ts3server_startscript.sh start serveradmin_password=$adminpwd createinifile=1 inifile=ts3server.ini > tsout.txt 2>&1"
    sleep 20
    su user-webi -c "./ts3server_startscript.sh stop"
    sleep 5
    pkill -u user-webi ts3server 2>/dev/null || true

    token=$(awk -F= '/token=/{print $2}' tsout.txt | tr -d '[:space:]')
    if [ -n "$token" ]; then
        echo "$token" > /home/tekbase_ts3.txt
        gen_logs "TeamSpeak token extracted and saved" msg
    else
        echo "No token generated." > /home/tekbase_ts3.txt
        gen_logs "Failed to extract TeamSpeak token" msg
    fi

    cat > ts3server.ini <<EOF
machine_id=
default_voice_port=9987
voice_ip=0.0.0.0
filetransfer_port=30033
query_port=10011
dbplugin=ts3db_sqlite3
dbsqlpath=sql/
dbconnections=10
logpath=logs
dbclientkeepdays=30
EOF

    su user-webi -c "touch query_ip_blacklist.txt query_ip_whitelist.txt"
    echo -e "127.0.0.1\n$local_ip" > query_ip_whitelist.txt

    configure_ts3_firewall

    su user-webi -c "./ts3server_startscript.sh start inifile=ts3server.ini"
    sleep 10

    if pgrep -u user-webi ts3server >/dev/null; then
        gen_logs "TeamSpeak started successfully" msg
        echo "Check teamspeak: ok" >> /home/tekbase_status.txt
    else
        gen_logs "TeamSpeak failed to start" msg
        echo "Check teamspeak: error" >> /home/tekbase_status.txt
    fi

    echo "Admin Login: serveradmin" >> /home/tekbase_ts3.txt
    echo "Admin Password: $adminpwd" >> /home/tekbase_ts3.txt
fi

##############################
# Install Linux Daemon       #
##############################
if [[ "$modsel" =~ ^(1|2|4|5|8|9)$ ]]; then
    cd /home/skripte
    daemonpwd=$(gen_passwd 8)
    daemonport=1500
    sed -i '/^password[[:space:]]*=/c\password = '"$daemonpwd"'' tekbase.cfg
    sed -i '/^listen_port[[:space:]]*=/c\listen_port = '"$daemonport"'' tekbase.cfg
    gen_logs "Set initial daemon password and port (1500)" ""

    while true; do
        daemonport=$((daemonport + 1))
        if [ "$netstat_inst" = "1" ]; then
            portcheck=$(netstat -tlpn 2>/dev/null | grep -w ":$daemonport")
        else
            portcheck=$(ss -tlpn 2>/dev/null | grep -w ":$daemonport")
        fi
        if [ -z "$portcheck" ]; then
            sed -i '/^listen_port[[:space:]]*=/c\listen_port = '"$daemonport"'' tekbase.cfg
            gen_logs "Free port $daemonport selected for daemon" ""
            break
        fi
    done

    echo "Daemon Port: $daemonport" > /home/tekbase_daemon.txt
    echo "Daemon Password: $daemonpwd" >> /home/tekbase_daemon.txt
    gen_logs "Daemon credentials saved" ""
fi

##############################
# Configure WWW              #
##############################
if [ "$modsel" -lt 8 ]; then
    site_url=$host_name
    wwwok=0

    possible_paths=(
        "/home/www/web0/html:/var/www/web0/html"
        "/var/www/vhosts/$site_url/httpdocs"
        "/var/www/vhosts/default/htdocs"
        "/var/www/virtual/default"
        "/srv/www/vhosts/$site_url/httpdocs"
        "/srv/www/vhosts/default/htdocs"
        "/srv/www/virtual/default"
        "/var/www/htdocs"
        "/srv/www/web0/html"
        "/srv/www/htdocs"
        "/srv/www"
        "/var/www/html"
        "/var/www"
    )

    for path_entry in "${possible_paths[@]}"; do
        base_path="${path_entry%%:*}"
        real_path="${path_entry##*:}"

        if [ -d "$base_path" ]; then
            wwwpath="${real_path:-$base_path}"
            wwwok=1
            [ -n "$local_ip" ] && [[ "$base_path" == "/srv/www" || "$base_path" == "/var/www" ]] && site_url="$local_ip"
            gen_logs "Web path found: $wwwpath for site $site_url" ""
            break
        fi
    done

    if [ "$wwwok" = "0" ]; then
        if [ "$os_install" = "1" ]; then
            mkdir -p /srv/www
            wwwpath="/srv/www"
        else
            mkdir -p /var/www
            wwwpath="/var/www"
        fi
        [ -n "$local_ip" ] && site_url="$local_ip"
        gen_logs "No known web path found. Created default: $wwwpath" ""
    fi

    chk_panel
    if [ "$web_panel" = "Plesk" ] && [ -d /var/www/vhosts ]; then
        select_url "/var/www/vhosts"
        wwwpath="/var/www/vhosts/$site_url/httpdocs"
        gen_logs "Plesk panel detected, selected path: $wwwpath" ""
    fi
fi

##############################
# Plesk                      #
##############################
if [ "$modsel" -lt 8 ] && [ "$web_panel" = "Plesk" ] && [ -d /var/www/vhosts ]; then
    if [ "$os_install" = "2" ]; then
        apt-get install $chkyes libgeoip-dev geoip-bin geoip-database libssh2-1-dev
        gen_logs "Installed Plesk dependencies (geoip, ssh2 libs)" ""
    fi

    cd /opt/plesk/php
    for phpd in */; do
        phpd=${phpd%/}
        if [[ "$phpd" =~ ^[0-9]+\.[0-9]+$ ]]; then
            phpv=${phpd//.}
            phpbin="/opt/plesk/php/${phpd}/bin"
            phplib="/opt/plesk/php/${phpd}/lib/php/modules"
            phpcfg="/opt/plesk/php/${phpd}/etc/php.d"

            if [ -d "$phpbin" ]; then
                for pkg in dev gd mbstring mysql xml; do
                    apt-get install $chkyes "plesk-php${phpv}-$pkg"
                    gen_logs "Installed plesk-php${phpv}-$pkg" ""
                done

                "$phpbin/pecl" install -f ssh2-1.4.1
                [ -f "$phplib/ssh2.so" ] && echo "extension=ssh2.so" > "$phpcfg/ssh2.ini"

                if [[ "$phpd" == 5.* || "$phpd" == 7.* ]]; then
                    "$phpbin/pecl" install -f geoip-1.1.1
                    [ -f "$phplib/geoip.so" ] && echo "extension=geoip.so" > "$phpcfg/geoip.ini"
                fi

                /etc/init.d/plesk-php${phpv}-fpm restart
                gen_logs "Restarted plesk-php${phpv}-fpm" ""
            fi
        fi
    done
fi

##############################
# Install TekBASE            #
##############################
if [ "$modsel" -lt 8 ]; then
    cd "$installhome"

    if [[ "$php_version" == "5.6" || "$php_version" == "7.0" ]]; then
        wget --no-check-certificate https://teklab.s3.amazonaws.com/tekbase_php56.zip
        gen_logs "Downloaded TekBASE for PHP $php_version" ""
    else
        wget --no-check-certificate https://teklab.s3.amazonaws.com/tekbase.zip
        gen_logs "Downloaded latest TekBASE" ""
    fi

    unzip tekbase*.zip && rm tekbase*.zip
    mv tekbase "$wwwpath"
    gen_logs "Unzipped and moved TekBASE to $wwwpath" ""

    tekpwd=$(gen_passwd 8)
    tekdb=$(gen_passwd 4)

    if [ "$os_install" = "2" ]; then
        mysqlpwd=$(awk '/password/ {print $3; exit}' /etc/mysql/debian.cnf)
        mysqlusr=$(awk '/user/ {print $3; exit}' /etc/mysql/debian.cnf)
    else
        mysqlusr="root"
        if [ -z "$mysqlpwd" ]; then
            clear
            if [ "$langsel" = "1" ]; then
                echo -e "Bitte geben Sie das MySQL Root Passwort ein:\n"
            else
                echo -e "Please input the MySQL Root password:\n"
            fi
            read -r mysqlpwd
        fi
    fi

    mysql --user="$mysqlusr" --password="$mysqlpwd" -e "
        SET sql_mode = '';
        CREATE DATABASE IF NOT EXISTS tekbase_$tekdb;
        GRANT ALL PRIVILEGES ON tekbase_$tekdb.* TO 'tekbase_$tekdb'@'localhost' IDENTIFIED BY '$tekpwd';
        FLUSH PRIVILEGES;
    "
    gen_logs "Created MySQL database tekbase_$tekdb and granted user access" ""

    mysql --user=tekbase_$tekdb --password=$tekpwd tekbase_$tekdb < "$wwwpath/tekbase/install/database.sql"
    rm -r "$wwwpath/tekbase/install"
    gen_logs "Imported initial TekBASE schema and removed installer" ""

    cat <<EOF > "$wwwpath/tekbase/config.php"
<?php
\$dbhost = "localhost";
\$dbuname = "tekbase_$tekdb";
\$dbpass = "$tekpwd";
\$dbname = "tekbase_$tekdb";
\$prefix = "teklab";
\$dbtype = "mysqli";
\$sitekey = "$tekpwd";
\$gfx_chk = "1";
\$ipv6 = "1";
\$shopcodes = "00000";
\$max_logins = "7";
\$awidgetone = "Members,group,members_all.php, ,3";
\$awidgetwo = "TekLab News,news,teklab_rss_all.php, ,2";
\$awidgetthree = "Admins,administrator,admins_all.php, ,1";
?>
EOF

    chmod 0777 "$wwwpath"/tekbase/{cache,pdf,resources,tmp}

    useradd -g users -p "$(perl -e 'print crypt("'$tekpwd'", "Sa")')" -s /bin/bash -m tekbaseftp -d "$wwwpath/tekbase"
    chown -R tekbaseftp:users "$wwwpath/tekbase"
    gen_logs "TekBASE config file created and permissions set" ""

    echo -e "DB Login: tekbase_$tekdb\nDB Password: $tekpwd" > /home/tekbase_db.txt
    echo -e "FTP Login: tekbaseftp\nFTP Password: $tekpwd" > /home/tekbase_ftp.txt

    sleep 5
    wget -q -O - "http://$site_url/tekbase/admin.php"
    gen_logs "Triggered admin.php setup via HTTP" ""
else
    rm -rf "$installhome/tekbase"
fi

wget -q --post-data "op=insert&$site_url" -O - http://licenses1.tekbase.de/wiauthorized.php
gen_logs "License inserted for $site_url" ""

##############################
# DB Inserts                 #
##############################
if [ "$local_ip" != "" ]; then
    if [ "$netstat_inst" = "1" ]; then
        ssh_port=$(netstat -tlpn | grep -e 'ssh' | awk -F ":" '{print $2}' | awk '{print $1}')
    else
        ssh_port=$(ss -tlpn | grep -e 'ssh' | awk -F ":" '{print $2}' | awk '{print $1}')
    fi
    if [ "$ssh_port" = "" ]; then
        ssh_port=22
    fi
    mysql --user=tekbase_$tekdb --password=$tekpwd tekbase_$tekdb << EOF
    INSERT INTO teklab_rootserver (id, sshdaemon, daemonpasswd, path, sshuser, sshport, name, serverip, loadindex, apps, games, streams, voices, vserver, web, cpucores, active) VALUES (NULL, "0", "$daemonpwd", "/home/skripte", "user-webi", "$ssh_port", "$local_ip", "$local_ip", "500", "1", "1", "1", "1", "1", "1", "$cpu_threads", "1");
    INSERT INTO teklab_teamspeak (id, serverip, queryport, admin, passwd, path, typ, rserverid) VALUES (NULL, "$local_ip", "10011", "serveradmin", "$adminpwd", "teamspeak3", "Teamspeak3", "1");
EOF
    gen_logs "Inserted rootserver and Teamspeak info into TekBASE DB" ""
fi


##############################
# Install SSH Keys           #
##############################
if [ "$modsel" != "3" ] || [ "$modsel" != "6" ]; then
    if [ ! -n "$yessel" ]; then
        select_sshkeys
        sshsel=0
    fi
    if [ "$sshsel" = "1" ]; then
        if [ ! -d "/home/user-webi/.ssh" ]; then
            mkdir "/home/user-webi/.ssh"
        else
            rm -r "/home/user-webi/.ssh"
            mkdir "/home/user-webi/.ssh"
        fi

        ssh-keygen -t rsa -b 4096 -N '' -f /home/user-webi/.ssh/id_rsa
        cp /home/user-webi/.ssh/id_rsa.pub /home/user-webi/.ssh/authorized_keys
        chown -R user-webi:users .ssh
        chmod 0700 .ssh

        gen_logs "Generated SSH keys for user-webi" ""

        if [ $modsel -lt 8 ]; then
            mv /home/user-webi/.ssh/id_rsa.* $wwwpath/tekbase/tmp
            gen_logs "Moved private/public SSH keys to TekBASE tmp dir" ""
        fi
    fi
fi

##############################
# TekBASE 8.x compatibility  #
##############################
cd /home/skripte
for FILE in $(find *.sh)
do
    cp $FILE ${FILE%.sh}
done
gen_logs "Converted .sh scripts to TekBASE 8.x compatible format" ""

##############################
# Finish                     #
##############################
cd $installhome
cd /usr/local
rm ioncube_x86-64.tar.gz
rm ioncube_x86.tar.gz
gen_logs "Cleaned up ioncube archives" ""

clear
if [ $modsel -lt 8 ]; then
    if [ "$langsel" = "1" ]; then
        echo "TekBASE wurde installiert. Sie können TekBASE über folgenden"
        echo "Browser Link aufrufen: http://$site_url/tekbase/admin.php"
        echo "Zwecks Freischaltung der Miet/Kaufversion diesen Link an"
        echo "service@teklab.de senden. Die Lite Version koennen Sie selbst"
        echo "im Kundenbereich freischalten."
        echo ""
        echo "Bei Plesk am besten unter Hosting Einstellungen die PHP Version"
        echo "auf 'X.X.XX (Vendor)' stellen bzw. PHP als 'Apache Modul' ausfuehren."
        echo "Dies ist nötig da ansonsten geoip und ioncube sowie ssh2 für die"
        echo "jeweilige PHP Version nachträglich kompiliert werden müssten."
        echo ""
        echo "Sollte TekBASE nicht aufrufbar sein, so schreiben Sie uns an"
        echo "Miet/Kaufversionen erhalten einen KOSTENLOSEN Installationssupport."
    else
        echo "TekBASE was installed. You can open TekBASE with this browser"
        echo "Link: http://$site_url/tekbase/admin.php"
        echo "Please send us an email with this link to service@teklab.de."
        echo "The Lite version can activated by yourself on our customer panel."
        echo ""
        echo "Is your TekBASE not available, please write us."
        echo "Rental/Buy versions get a FREE installation support."
    fi
    echo ""
    gen_logs "TekBASE installation complete – Admin: http://$site_url/tekbase/admin.php" ""
fi

if [ "$modsel" = "1" ] || [ "$modsel" = "4" ] || [ "$modsel" = "8" ]; then
    if [ "$langsel" = "1" ]; then
        echo "Der Teamspeak 3 Grundserver wurde installiert. Das Serveradmin"
        echo "Passwort finden Sie in /home/tekbase_ts3.txt"
    else
        echo "The Teamspeak 3 server was installed. You will find the"
        echo "Serveradmin password in /home/tekbase_ts3.txt"
    fi
    echo ""
    gen_logs "Teamspeak 3 base server installed" ""
fi

if [ "$modsel" = "1" ] || [ "$modsel" = "2" ] || [ "$modsel" = "4" ] || [ "$modsel" = "5" ] || [ "$modsel" = "8" ] || [ "$modsel" = "9" ]; then
    if [ "$langsel" = "1" ]; then
        echo "Der Rootserver wurde komplett eingerichtet. Die Linux Daemon"
        echo "Zugangsdaten stehen in der /home/tekbase_daemon.txt Datei."
        echo "Der Linux Daemon benoetigt kein SSH und arbeitet auch deutlich"
        echo "schneller. Um den Linux Daemon zu starten bitte folgendes"
        echo "ausfuehren:"
        echo "su user-webi"
        echo "cd /home/skripte"
        echo "screen -A -m -d -S tekbasedaemon ./server"
    else
        echo "The root server has been completely set up. The linux daemon"
        echo "credentials are in the file /home/tekbase_daemon.txt."
        echo "The linux daemon does not require SSH and works much faster."
        echo "To start the linux daemon please run the following:"
        echo "su user-webi"
        echo "cd /home/skripte"
        echo "screen -A -m -d -S tekbasedaemon ./server"
    fi
    echo ""
    gen_logs "Linux daemon setup complete — startup instructions shown" ""
fi

if [ "$os_install" = "2" ]; then
    export DEBIAN_FRONTEND=dialog
fi

exit 0

#!/bin/bash
#Automation for VIOS update
#VIOS update is different from VIOS upgrade, please read VIOS docs for more details.

set -o errexit
set -o nounset
set -o pipefail

REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PASSWORD=""
SFTP_DOMAIN=""
SFTP_USER=""
SFTP_PASSWORD=""
VIOS_FIX_VER=""
MAX_ATTEMPTS=10
attempts=0

function set_sftp_details(){
    current_directory=$(pwd)
    file_path="$current_directory/set_sftp.sh"
    touch "$file_path"
    exec 3>"$file_path"
    echo "export SFTP_DOMAIN=$SFTP_DOMAIN" >&3
    echo "export SFTP_USER=$SFTP_USER" >&3
    echo "export SFTP_PASSWORD=$SFTP_PASSWORD" >&3
    exec 3>&-
    sshpass -p "${REMOTE_PASSWORD}" scp -O "$file_path" "${REMOTE_USER}@${REMOTE_HOST}:/home/padmin"
}

function verify_update(){
    sshpass -p "${REMOTE_PASSWORD}" ssh "${REMOTE_USER}@${REMOTE_HOST}" << EOF
    oem_setup_env
    expected_output="Current system settings are up to date"
    output=\`rulescfgset\`
    echo "Output \$output"
    if [ "\$output" == "\$expected_output" ]; then
        vios_version=\`/usr/ios/cli/ioscli ioslevel\`
        echo "VIOS upgraded successfully to \$vios_version"
    else
       echo "Rules did not apply successfully, please try again!"
    fi
EOF
}


function new_rules(){
    sshpass -p "${REMOTE_PASSWORD}" ssh "${REMOTE_USER}@${REMOTE_HOST}" << EOF
    oem_setup_env
    /usr/bin/expect << EOF
        spawn rulescfgset
        expect "The recent software updates have modified the system rules. These modifications have not been deployed on the system. Do you want to deploy the new rules ontop of the current system settings now \[y/N\]?"
        send "y\r"
        set timeout -1
        expect eof
EOF
}

function apply_rules(){
    sshpass -p "${REMOTE_PASSWORD}" ssh "${REMOTE_USER}@${REMOTE_HOST}" << EOF
    oem_setup_env
    rules -o deploy -d
EOF
}

ping_host() {
    host="$1"
    if ping -c 1 -W 1 "$host" &> /dev/null; then
      return 0  # Successful ping
    else
      return 1  # Unsuccessful ping
    fi
}

function restart_vios(){
    sleep 300
    sshpass -p "${REMOTE_PASSWORD}" ssh "${REMOTE_USER}@${REMOTE_HOST}" << EOF
        echo "Restarting the VIOS"
        oem_setup_env
        /usr/bin/expect << EOF
        spawn /usr/ios/cli/ioscli shutdown -restart
        expect "Shutting down the VIO Server could affect Client Partitions. Continue \[y|n\]?"
        send "y\r"
        set timeout 10
        expect eof
EOF
    sleep 60
    while [ $attempts -lt $MAX_ATTEMPTS ]; do
    attempts=$((attempts + 1))
    echo "Attempting to ping VIOS (Attempt $attempts)..."
    if ping_host ${REMOTE_HOST}; then
       echo "VIOS restarted"
       break
    fi
    echo "Ping failed. Retrying in 1 minute..."
    sleep 60
    done
    if [ $attempts -eq $MAX_ATTEMPTS ]; then
        echo "Ping failed.VIOS is down, please check manually."
        exit 1
    fi
}

function vios_update(){
    sshpass -p "${REMOTE_PASSWORD}" ssh "${REMOTE_USER}@${REMOTE_HOST}" << EOF
        oem_setup_env
        echo "Verifying if all required files are downloaded for fix"
        cp /home/padmin/vios_update/ck_sum.bff /home/padmin
        chmod 755 /home/padmin/ck_sum.bff
        /home/padmin/ck_sum.bff vios_update
        cd ..
        /usr/ios/cli/ioscli updateios -commit
        echo "Running VIOS update command"
        /usr/bin/expect << EOF
            spawn /usr/ios/cli/ioscli updateios -accept -install -dev /home/padmin/vios_update
            expect "Continue the installation \[y|n\]?"
            send "y\r"
            set timeout -1
            expect eof
EOF
}

function pre_vios_update(){
    # SSH into the VIOS
    set_sftp_details
    sshpass -p "${REMOTE_PASSWORD}" ssh "${REMOTE_USER}@${REMOTE_HOST}" << EOF
        echo "Logged into the VIOS.."
        oem_setup_env
        # Create a link to openssl
        ln -s /usr/bin/openssl /usr/ios/utils/openssl
        # Verify the link to openssl was created
        ls -alL /usr/bin/openssl /usr/ios/utils/openssl
        mkdir -p vios_update && cd vios_update
        echo "Created directory vios_update"
        echo "Connecting to FTP server and downloading VIOS fix pack for \${VIOS_FIX_VER}"
        . /home/padmin/set_sftp.sh
        /usr/bin/expect << EOF
            spawn sftp "\${SFTP_USER}@\${SFTP_DOMAIN}"
            expect "password:"
            send "\${SFTP_PASSWORD}\r"
            expect "sftp>"
            send "mget *\r"
            set timeout -1
            expect "sftp>"
            send "bye\r"
            expect eof
EOF
}

function parseArgs(){
    while [ $# -gt 0 ]
    do
        case "$1" in
            --remote-host) REMOTE_HOST="$2"; shift;;
            --remote-user) REMOTE_USER="$2"; shift;;
            --remote-password) REMOTE_PASSWORD="$2"; shift;;
            --sftp-doamin) SFTP_DOMAIN="$2"; shift;;
            --sftp-user) SFTP_USER="$2"; shift;;
            --sftp-password) SFTP_PASSWORD="$2"; shift;;
            --vios-fix) VIOS_FIX_VER="$2"; shift;;
            --) shift;;
             esac
             shift;
    done
}

function main() {
    parseArgs "$@"
    pre_vios_update
    vios_update
    restart_vios
    apply_rules
    restart_vios
    new_rules
    verify_update
}

main "$@"
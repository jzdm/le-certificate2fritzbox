#!/usr/bin/env bash
#
# DESCRIPTION
#   Simple script to import a Let's Encrypt certificate to a FRITZ!Box.
#   Inspired by https://www.synology-forum.de/threads/automatisierte-lets-encrypt-erneuerung-inkl-portfreigabe-fritz-box-integration.106559/post-860429
# 
# SETUP
#   copy file 'credentials.sample' to 'credentials' and insert username, password and the FRITZ!Box hostname into first, 2nd and 3rd line.
#
# USAGE
#   Make sure to first copy the desired LE-certificate to the 'cert' subfolder, then call this script.
#   The certificate files must be named as 'cert.pem', fullchain.pem' and 'privkey.pem'
#   
#   ./fbleup.sh [--checkCert]
#       --checkCert    compares expiration dates of local and remote certificate and only updates if the expiration date is different.
#
#
# This program comes without any warranties. Use at your own risk.
# 
# Changelog:
#
# 2023-08-22
#   Initial version by "jzdm <fbleupdater@jzdm.de>"
#

cd "$(dirname "$0")"

LoggerTag="FBLEup"
LoggerCmd="-t ${LoggerTag}"

function usage () {
    echo "Simple script to import a Let's Encrypt certificate to a FRITZ!Box."
    echo ""
    echo "Usage:"
    echo "  " $1 " [--checkCert]"
    echo "      --checkCert   compares expiration dates of local and remote certificate and only updates if the expiration date is different."
    echo ""
}

# check user input first
if [ "$1" = "-h" ] || [ "$1" = "--h" ] || [ "$1" = "-help" ] || [ "$1" = "--help" ]; then
    usage $0
    exit 0
fi



logger ${LoggerCmd} "Run FRITZ!Box Let's Encrypt certificate importer."

# read FRITZ!Box user credentials from this file
CREDENTIALSFILE="credentials"

# read user credentials and hostname from file
USERNAME=$( sed -n '1{p;q;}' "${CREDENTIALSFILE}" )
PASSWORD=$( sed -n '2{p;q;}' "${CREDENTIALSFILE}" )
HOST=$( sed -n '3{p;q;}' "${CREDENTIALSFILE}" )

# path of folder containing the certificate files. privkey.pem and fullchain.pem
CERTPATH="./cert"
CERTPASSWORD=""

# optionally check certificate expiration date
CERTCHECK=false
if [ ! -z "$1" ]; then
    case $1 in
        "--checkCert")
            CERTCHECK=true
            logger ${LoggerCmd} "Will check certificate expiration."
        ;;
        *)
            logger ${LoggerCmd} "Unknown first argument. Please check usage."
        ;;
    esac
fi

if [ "${CERTCHECK}" = true ]; then
    ./tlsCExp.sh "${HOST}" "${CERTPATH}/cert.pem"
    if [ $? -eq 0 ]; then
        logger ${LoggerCmd} "No update needed. Exiting."
        exit 0
    else
        logger ${LoggerCmd} "Update needed. Continue."
    fi
fi



# log the user in at the FRITZ!Box
logger ${LoggerCmd} "Login user to FRITZ!Box."
CHALLENGE=$( curl -k -s "https://${HOST}/login_sid.lua" | sed -e 's/^.*<Challenge>//' -e 's/<\/Challenge>.*$//' )
HASH=$( echo -n "${CHALLENGE}-${PASSWORD}" | iconv -f ASCII -t UTF-16LE | md5sum | awk '{print $1}' )
SID=$( curl -k -s "https://${HOST}/login_sid.lua?sid=0000000000000000&username=${USERNAME}&response=${CHALLENGE}-${HASH}" | sed -e 's/^.*<SID>//' -e 's/<\/SID>.*$//' )

if [[ $SID == "0000000000000000" ]]
then
    logger ${LoggerCmd} "Failed to authenticate user."
    exit 1
else
    logger ${LoggerCmd} "User logged in."

    # create temp file to store form data
    TMP=""
    TMP="$(mktemp -t fbletmpfile)"
    trap 'rm -f "$TMP"' exit
    chmod 600 "$TMP"

    logger ${LoggerCmd} "Temp file created as ${TMP}"

    BOUNDARY="---------------------------"$(date +%Y%m%d%H%M%S)
    (
    printf -- "--%s\r\n" "$BOUNDARY"
    printf "Content-Disposition: form-data; name=\"sid\"\r\n\r\n%s\r\n" "$SID"
    printf -- "--%s\r\n" "$BOUNDARY"
    printf "Content-Disposition: form-data; name=\"BoxCertPassword\"\r\n\r\n%s\r\n" "${CERTPASSWORD}"
    printf -- "--%s\r\n" "$BOUNDARY"
    printf "Content-Disposition: form-data; name=\"BoxCertImportFile\"; filename=\"BoxCert.pem\"\r\n"
    printf "Content-Type: application/octet-stream\r\n\r\n"
    cat "${CERTPATH}/privkey.pem"
    cat "${CERTPATH}/fullchain.pem"
    printf "\r\n"
    printf -- "--%s--" "$BOUNDARY"
    ) >> "$TMP"
    
    # upload the certificate to the FRITZ!Box
    #RESPONSE=$(wget -q -O - "$HOST/cgi-bin/firmwarecfg" --header="Content-type: multipart/form-data boundary=$BOUNDARY" --post-file "$TMP" | grep SSL)
    RESPONSE=$( curl -k -s -X POST  -H "Content-type: multipart/form-data boundary=${BOUNDARY}" --data-binary @"${TMP}" "https://${HOST}/cgi-bin/firmwarecfg")
    
    if [ $? -ne 0 ]
    then
        logger ${LoggerCmd} "Certificate upload returned an error."
        exit 1
    else
        # check if RESPONSE contains a success message
        # probably only in german or english
        # different languages must be added here
        grep -q -e 'erfolgreich' -e 'success' <<< $RESPONSE
        if [ $? -ne 0 ]; then
            logger ${LoggerCmd} "Certificate renewal probably failed."
            exit 1
        fi

        logger ${LoggerCmd} "Successfully renewed FRITZ!Box certificate."
    fi
fi

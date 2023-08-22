#!/usr/bin/env bash

# tlsCExp.sh compares the expiration dates of TLS certificates of a domain and a local certificate file
# 
# Usage:
#   ./tlsCExp.sh DomainName CertFile [ PortNumber ]
#     DomainName - like www.example.com
#     CertFile   - like /etc/letsencrypt/live/www.example.com/cert.pem
#     PortNumber - like 8443, optional, defaults to 443
#
# Return values:
#     0   - Online and offline certificate expire at same time.
#     1   - Offline certificate expires first.
#     2   - Online certificate expires first.
#     127 - An error occured.
#
# This program comes without any warranties. Use at your own risk.
# 
# Changelog:
#
# 2022-08-14
#   Initial version by "jzdm <tlscexp@jzdm.de>"
#

LoggerTag="tlsCExp"
LoggerCmd="-t ${LoggerTag}"

function usage () {
	echo "Usage:"
	echo "  " $1 "DomainName CertFile [ PortNumber ]"
	echo "      DomainName - like www.example.com"
	echo "      CertFile   - like /etc/letsencrypt/live/www.example.com/cert.pem"
	echo "      PortNumber - like 8443, optional, defaults to 443"
	echo ""
	echo "Return values:"
	echo "      0   - Online and offline certificate expire at same time."
	echo "      1   - Offline certificate expires first."
	echo "      2   - Online certificate expires first."
	echo "      127 - An error occured."
	echo ""
}

# check user input first
if [ -z "$2" ] || [ "$2" = "-h" ] || [ "$2" = "--h" ] || [ "$2" = "-help" ] || [ "$2" = "--help" ]; then
	usage $0
	exit 0
fi

# setup variables
Domain="$1"
CertFile="$2"
Port="443"
if [ ! -z "$3" ]; then
	Port="$3"
fi


# certificate comparison:
logger ${LoggerCmd} "Checking certificate expiration for domain \"${Domain}\"."

# check online certificate
expDateOnline=$( echo "Q" | openssl s_client -servername ${Domain} -connect ${Domain}:${Port} 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | grep -e '^notAfter' )
if [ $? -ne 0 ]; then
	logger ${LoggerCmd} -s "Online check failed."
	exit -1
fi

# check local/offline certificate
expDateOffline=$( openssl x509 -enddate -noout -in ${CertFile} )
if [ $? -ne 0 ]; then
	logger ${LoggerCmd} -s "Offline check failed."
	exit -1
fi

# extract date string
pref="notAfter="
expDateOffline=${expDateOffline#"$pref"}
expDateOnline=${expDateOnline#"$pref"}

# transform to POSIX time
# either use GNU or BSD 'date'
if date -v -1d &> /dev/null; then
	# BSD
	expDatePosixOffline=$( date -j -f "%b %d %T %Y %Z" "${expDateOffline}" +%s )
	expDatePosixOnline=$(  date -j -f "%b %d %T %Y %Z" "${expDateOnline}"  +%s )
else
	# GNU
	expDatePosixOffline=$( date -d "${expDateOffline}" +%s )
	expDatePosixOnline=$(  date -d "${expDateOnline}" +%s )
fi

# compare expiration dates and return result
if [ "${expDatePosixOnline}" -eq "${expDatePosixOffline}" ]; then
	# expiration at same time
	logger ${LoggerCmd} -s "Offline and online certificate expire at same time:"
	logger ${LoggerCmd} -s "${expDateOffline}"
	exit 0
elif [ "${expDatePosixOnline}" -gt "${expDatePosixOffline}" ]; then
	# offline certificate expires first
	logger ${LoggerCmd} -s "Offline certificate expires first:"
	logger ${LoggerCmd} -s "${expDateOffline}"
	exit 1
elif [ "${expDatePosixOnline}" -lt "${expDatePosixOffline}" ]; then
	# online certificate expires first
	logger ${LoggerCmd} -s "Online certificate expires first:"
	logger ${LoggerCmd} -s "${expDateOnline}"
	exit 2
else
	# weird errors happened
	logger ${LoggerCmd} -s "Odd things happened. Quitting with error."
	exit -1
fi

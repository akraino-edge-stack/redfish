#!/bin/bash
#
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Script to get Dell nic settings.
#
# usage:  ./get_dellnicmac.sh [--rc settingsfile] [--nic FQDD] [--help]
#

RCFILE=
FQDD=

# PROCESS COMMAND LINE ARGUMENTS
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --rc)
    RCFILE=$2
    shift # past argument
    shift # past value
    ;;
    --nic)
    FQDD=$2
    shift # past argument
    shift # past value
    ;;
    --help)
    echo "usage:  ./get_dellnicmac.sh [--rc settingsfile] [--nic FQDD] [--help]"
    exit 0
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# SETUP TOOLS AND LOAD DEFAULT BUILD VARIABLES
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $BASEDIR/setup_tools.sh 1>&2

# LOAD SERVER VARIABLES IF SERVER RCFILE PROVIDED - OTHERWISE ASSUME THE VARIABLES HAVE BEEN EXPORTED
if [ -n "$RCFILE" ] && [ -f "$RCFILE" ]; then
    source $RCFILE
fi

# CHECK A FEW REQUIRED VARIABLES - BUT NOT ALL
if [ -z "$SRV_NAME" ] || [ -z "$SRV_OOB_IP" ] || [ -z "$SRV_OOB_USR" ] || [ -z "$SRV_OOB_PWD" ]; then
    echo "ERROR:  Invalid or missing variables in rcfile [$RCFILE]"
    exit 1
fi

# CHECK IF NIC VALUE PASSED - OTHERWISE USE SRV_HTTP_BOOT_DEV
if [ -z "$FQDD" ] && [ -z "$SRV_HTTP_BOOT_DEV" ] ; then
    echo "ERROR:  parameter --nic [$FQDD] or variable SRV_HTTP_BOOT_DEV [$SRV_HTTP_BOOT_DEV] required"
    exit 1
fi

if [ -z "$FQDD" ] ; then
    FQDD=$SRV_HTTP_BOOT_DEV
fi

## GET NIC SETTINGS USING REDFISH - BYPASS PROXY FOR INTERNAL CONNECTION TO IDRAC
NIC_DETAILS=$(HTTPS_PROXY= https_proxy= python -u "$DELL_ROOT/Redfish Python/GetEthernetInterfacesREDFISH.py"  -ip $SRV_OOB_IP -u $SRV_OOB_USR -p $SRV_OOB_PWD -d $FQDD)
if [ "$?" -ne 0 ]; then
    echo "ERROR:  failed to get nic settings"
    exit 1
fi

## DONE
echo "$NIC_DETAILS" | grep "^MACAddress" | grep -o "..:..:..:..:..:.." | tr '[:upper:]' '[:lower:]'


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
# Script to apply Dell BIOS and/or RAID settings.
#
# usage:  ./apply_dellxml.sh [--rc settingsfile] --template templatefile [--no-confirm] [--no-apply-hw] [--help]
#

# default behavior will require confirmation before starting
NO_CONFIRM=${NO_CONFIRM:-}
NO_APPLY_HW=${NO_APPLY_HW:-}
RCFILE=
TEMPLATE=

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
    --template)
    TEMPLATE=$2
    shift # past argument
    shift # past value
    ;;
    --no-confirm|--skip-confirm)
    NO_CONFIRM=TRUE
    shift # past argument
    ;;
    --no-apply-hw|--skip-biosraid)
    echo "WARNING:  This run will only create the xlm file and not apply BIOS and RAID configuration.  This is for testing only."
    NO_APPLY_HW=TRUE
    shift # past argument
    ;;
    --help)
    echo "usage:  ./apply_dellxml.sh [--rc settingsfile] --template templatefile [--no-confirm] [--no-apply-hw] [--help]"
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
CHECKLIST="SRV_NAME SRV_OOB_IP SRV_OOB_USR SRV_OOB_PWD"
for VAR in $CHECKLIST; do
    if [ -z "${!VAR}" ] ; then
        echo "ERROR:  Invalid or missing variable [$VAR] = [${!VAR}] in rcfile [$RCFILE]"
        echo "usage:  ./apply_dellxml.sh [--rc settingsfile] --template templatefile [--no-confirm] [--no-apply-hw] [--help]"
        exit 1
    fi
done

# CHECK IF TEMPLATE PASSED AND EXISTS
if [ -z "$TEMPLATE" ] || ! [ -f "$REDFISH_ROOT/$TEMPLATE" ]; then
    echo "ERROR:  Invalid or missing template file [$REDFISH_ROOT/$TEMPLATE]"
    echo "usage:  ./apply_dellxml.sh [--rc settingsfile] --template templatefile [--no-confirm] [--no-apply-hw] [--help]"
    exit 1
else
    echo "Using template [$REDFISH_ROOT/$TEMPLATE]"
fi

# SET ADDITIONAL VARIABLES BASED ON RC FILE
SRV_IPXE_URL=http://$BUILD_WEBIP:$BUILD_WEBPORT/ipxe.efi
XMLFILE=$SRV_NAME.${TEMPLATE%\.template}

# CHECK VARIABLES USED IN TEMPLATE
CHECKLIST=$(grep -oP '(?<=@@)[^@]+(?=@@)' "$REDFISH_ROOT/$TEMPLATE" | sort | uniq | xargs)
for VAR in $CHECKLIST; do
    if [ -z "${!VAR}" ] ; then
        echo "ERROR:  Invalid or missing variable [$VAR] = [${!VAR}] required by template [$TEMPLATE]"
        echo "usage:  ./apply_dellxml.sh [--rc settingsfile] --template templatefile [--no-confirm] [--no-apply-hw] [--help]"
        exit 1
    fi
done

if [ -z "$NO_CONFIRM" ]; then
    echo ""
    read -r -p "Preparing to apply xml file [$TEMPLATE] to server [$SRV_NAME] using oob ip [$SRV_OOB_IP].  Are you sure? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            echo "Script aborted!"
            exit 1
            ;;
    esac
    echo ""
else
    i="10"
    echo -n "WARNING:  Preparing to apply xml to server [$SRV_NAME] using oob ip [$SRV_OOB_IP].  Beginning in $i seconds "
    while [ $i -gt 0 ]; do
        echo -n "."; sleep 1; i=$[$i-1]
    done
    echo ""
fi

echo "Beginning create and apply xlm file to server at" `date`
STIME=$(date +%s)

## CREATE HARDWARE CONFIG XML FILE FOR USE WITH REDFISH
echo "Creating server BIOS/RAID settings file [$BUILD_ROOT/$XMLFILE] for server [$SRV_NAME]"
mkdir -p $BUILD_ROOT
rm -f $BUILD_ROOT/$XMLFILE
cp -f $REDFISH_ROOT/$TEMPLATE $BUILD_ROOT/$XMLFILE

for VAR in $(set | grep -P "^SRV_|^BUILD_" | cut -f 1 -d'='); do
    sed -i -e "s|@@$VAR@@|${!VAR}|g" $BUILD_ROOT/$XMLFILE
done

## CHECK THAT ALL VALUES WERE REPLACED
MISSING=$(grep -Po "@@.*?@@" $BUILD_ROOT/$XMLFILE | sort | uniq)
if [ -n "$MISSING" ] ; then
    echo "ERROR:  Required variable(s) in template [$TEMPLATE] were not located in the resource file [$RCFILE]"
    echo ${MISSING//@@/} | xargs -n 1 | sed -e 's/^/        /g'
    exit 1
fi

if [ -z "$NO_APPLY_HW" ]; then

    ## PUSH HARDWARE CONFIG XML USING REDFISH - BYPASS PROXY FOR INTERNAL CONNECTION TO IDRAC
    echo "Applying server settings file [$BUILD_ROOT/$XMLFILE] to [$SRV_OOB_IP]"
    echo "This step could take up to 10 minutes"
    HTTPS_PROXY= https_proxy= python -u "$DELL_ROOT/Redfish Python/ImportSystemConfigurationLocalFilenameREDFISH.py" \
        -ip $SRV_OOB_IP -u $SRV_OOB_USR -p $SRV_OOB_PWD -t ALL -f $BUILD_ROOT/$XMLFILE -s Forced 2>&1 | \
        awk '{if (NF>0) {print $0; fflush();}} /FAIL/ {T=1;} END {exit $T;}'
    if [ "$?" -ne 0 ]; then
        echo "ERROR:  failed applying server BIOS/RAID settings"
        exit 1
    fi
else
    ## SKIPPING REBOOT
    echo "WARNING:  Skipping application of hardware settings - normally used for testing only"
fi

## DONE
ETIME=$(date +%s)
echo "SUCCESS:  Completed update of BIOS/RAID settings on [$SRV_NAME] at" `date`
echo "Elapsed time was $(( ($ETIME - $STIME) / 60 )) minutes and $(( ($ETIME - $STIME) % 60 )) seconds"



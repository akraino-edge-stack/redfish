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
# Script to update webroot with ubuntu os files.
#
# usage:  ./update_webroot.sh [--rc settingsfile] [--iso ubuntu.iso] [--help]

# Define Variables
#
UBUNTU_ISO=${UBUNTU_ISO:-}  ## MUST BE PASSED BY USER OR CALLING SCRIPT

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
    --iso)
    UBUNTU_ISO=$2
    shift # past argument
    shift # past value
    ;;
    --help)
    echo "usage:  ./update_webroot.sh [--rc settingsfile] [--iso ubuntu.iso] [--help]"
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
. $BASEDIR/setup_tools.sh

# LOAD SERVER VARIABLES IF SERVER RCFILE PROVIDED - OTHERWISE ASSUME THE VARIABLES HAVE BEEN EXPORTED
if [ -n "$RCFILE" ] && [ -f "$RCFILE" ]; then
    source $RCFILE
fi

echo "Checking iso [$UBUNTU_ISO]"

## CHECK IF ISO EXISTS
if [ -n "$UBUNTU_ISO" ] && [ ! -f $UBUNTU_ISO ]; then 
    echo "ERROR:  ISO file [$UBUNTU_ISO] does not exists"
    exit 1
fi

## CHECK IF ISO IS VALID
mkdir -p $WEB_ROOT
if [ -z $UBUNTU_ISO ] || ! xorriso --indev $UBUNTU_ISO --check-media &>/dev/null; then 
    echo "WARNING:  ISO file [$UBUNTU_ISO] appears to be missing or corrupt.  Downloading instead."
    xorriso --indev $UBUNTU_ISO --check-media 2>&1 | sed -e "s/^/    /g"
    export UBUNTU_ISO=${UBUNTU_URL##*/}
    echo "WARNING:  Attempting to use [$UBUNTU_ISO] instead."
    if ! [ -f $WEB_ROOT/$UBUNTU_ISO ]; then 
        echo "Downloading Ubuntu iso from [$UBUNTU_URL] to [$UBUNTU_ISO]"
        curl -Lo $WEB_ROOT/$UBUNTU_ISO $UBUNTU_URL
    else
        echo "Ubuntu iso [$UBUNTU_ISO] already exists in [$WEB_ROOT]"
    fi
else
    cp $UBUNTU_ISO $WEB_ROOT/${UBUNTU_ISO##*/}
fi
UBUNTU_ISO=$WEB_ROOT/${UBUNTU_ISO##*/}

echo "Updating web root folder [$WEB_ROOT] with ubuntu iso [$UBUNTU_ISO] contents"
## CHECK AGAIN IF ISO EXISTS/IS ISO FORMAT
if [ ! -f $UBUNTU_ISO ] || ! xorriso --indev $UBUNTU_ISO --check-media &>/dev/null; then 
    echo "ERROR:  ISO file [$UBUNTU_ISO] does not exists or is corrupt"
    xorriso --indev $UBUNTU_ISO --check-media | sed -e "s/^/    /g"
    exit 1
fi

## EXTRACT README.diskdefines
xorriso -osirrox on -indev $UBUNTU_ISO -extract /README.diskdefines $UBUNTU_ISO.README.diskdefines &>/dev/null

## GET ISO VERSION/ARCH
ISO_VERSION=$(grep -oh "[0-9]*\.[0-9]*\.[0-9]*" $UBUNTU_ISO.README.diskdefines)
ISO_ARCH=$(grep "#define ARCH " $UBUNTU_ISO.README.diskdefines | awk '{print $3}')
if [ -z "$ISO_VERSION" ] || [ -z "$ISO_ARCH" ]; then
    echo "FAILED:  Unable to determine version [$ISO_VERSION] or arch [$ISO_ARCH] from iso [$UBUNTU_ISO]"
    exit 1
fi
echo "Found ubuntu version [ISO_VERSION] arch [$ISO_ARCH]"
rm -f $UBUNTU_ISO.README.diskdefines

## CREATE ROOT FOLDER
UBUNTU_ROOT=ubuntu-$ISO_VERSION-$ISO_ARCH
UBUNTU_FOLDER=$WEB_ROOT/$UBUNTU_ROOT
mkdir -p $UBUNTU_FOLDER

## COPY FILES
echo "Extracting files to [$WEB_ROOT]"
cp -f $REDFISH_ROOT/sources.list $WEB_ROOT
xorriso -osirrox on:auto_chmod_on -indev $UBUNTU_ISO -find / -type d -exec chmod u+rwx -- -extract / $UBUNTU_FOLDER -rollback_end 2>&1 | sed -e "s/^/    /g"

## EXPAND KERNEL AND INITRD (HWE AND STANDARD)
HWE_OIMAGE=linux-generic-hwe-${ISO_VERSION%.*}
HWE_KERNEL=linux-hwe-$ISO_VERSION-$ISO_ARCH
HWE_INITRD=initrd-hwe-$ISO_VERSION-$ISO_ARCH
cp -f $UBUNTU_FOLDER/install/hwe-netboot/ubuntu-installer/$ISO_ARCH/linux $WEB_ROOT/$HWE_KERNEL
gunzip -c $UBUNTU_FOLDER/install/hwe-netboot/ubuntu-installer/$ISO_ARCH/initrd.gz > $WEB_ROOT/$HWE_INITRD

STD_OIMAGE=linux-generic-${ISO_VERSION%.*}
STD_KERNEL=linux-$ISO_VERSION-$ISO_ARCH
STD_INITRD=initrd-$ISO_VERSION-$ISO_ARCH
cp -f $UBUNTU_FOLDER/install/netboot/ubuntu-installer/$ISO_ARCH/linux $WEB_ROOT/$STD_KERNEL
gunzip -c $UBUNTU_FOLDER/install/netboot/ubuntu-installer/$ISO_ARCH/initrd.gz > $WEB_ROOT/$STD_INITRD

## CREATE SCRIPT-ISO_VERSION-ISO_ARCH.IPXE FILE
sed -e "s|@@KERNEL@@|$HWE_KERNEL|g" \
    -e "s|@@INITRD@@|$HWE_INITRD|g" \
    -e "s|@@BASE_KERNEL@@|$HWE_OIMAGE|g" \
    -e "s|@@UBUNTU_ROOT@@|$UBUNTU_ROOT|g" \
    $REDFISH_ROOT/script.ipxe.template > $WEB_ROOT/script-hwe-$ISO_VERSION-$ISO_ARCH.ipxe

sed -e "s|@@KERNEL@@|$STD_KERNEL|g" \
    -e "s|@@INITRD@@|$STD_INITRD|g" \
    -e "s|@@BASE_KERNEL@@|$STD_OIMAGE|g" \
    -e "s|@@UBUNTU_ROOT@@|$UBUNTU_ROOT|g" \
    $REDFISH_ROOT/script.ipxe.template > $WEB_ROOT/script-$ISO_VERSION-$ISO_ARCH.ipxe

echo "Files for Ubuntu version [$ISO_VERSION] [$ISO_ARCH] are ready in folder [$WEB_ROOT]"
echo "Use script-hwe-$ISO_VERSION-$ISO_ARCH.ipxe or script-$ISO_VERSION-$ISO_ARCH.ipxe in the dhcp config depending on the kernel version required."


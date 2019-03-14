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
# Script to create webroot for ubuntu os install.
#
# usage:  ./create_ipxe.sh [--rc settingsfile] [--help]

# Define Variables
#
RCFILE=

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
    --help)
    echo "usage:  ./create_ipxe.sh [--rc settingsfile] [--help]"
    exit 0
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# LOAD BUILD DEFAULT VALUES IF BUILD VARIABLES ARE NOT LOADED
if [ -z "$AKRAINO_ROOT" ]; then
    BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    if [ -z "$BASEDIR" ] || ! [ -f "$BASEDIR/buildrc" ]; then
        echo "ERROR:  Invalid or missing build variables rcfile [$BASEDIR/buildrc]"
        exit 1
    fi
    source "$BASEDIR/buildrc"
fi

# LOAD SERVER VARIABLES IF SERVER RCFILE PROVIDED - OTHERWISE ASSUME THE VARIABLES HAVE BEEN EXPORTED
if [ -n "$RCFILE" ] && [ -f "$RCFILE" ]; then
    source $RCFILE
fi

IPXE_VLAN=${IPXE_VLAN:-1}
IPXE_INTF=${IPXE_INTF:-net1}

## CHECK IF IPXE EFI FILE ALREADY EXISTS
if [ -f "$WEB_ROOT/ipxe-$IPXE_INTF-$IPXE_VLAN.efi" ]; then
    echo "Skipping ipxe build because efi file [$WEB_ROOT/ipxe-$IPXE_INTF-$IPXE_VLAN.efi] already exists"
    exit 0
fi

## GIT CLONE IPXE IF $IPXE_ROOT DOES NOT EXIST
if [ ! -d "$IPXE_ROOT" ]; then
    echo "Cloning ipxe source from [$IPXE_GIT] to [$IPXE_ROOT]"
    git clone $IPXE_GIT $IPXE_ROOT
fi

## ENABLE VLAN SUPPORT
if [ ! -f "$IPXE_ROOT/src/config/general.h" ]; then
    echo "ERROR:  Could not find config file [$IPXE_ROOT/src/config/general.h]"
    exit 1
fi
sed -i 's|//#define VLAN_CMD|#define VLAN_CMD|g' $IPXE_ROOT/src/config/general.h

## CREATE BOOT.IPXE
rm -f $IPXE_ROOT/boot.ipxe
sed -e "s|@@IPXE_VLAN@@|$IPXE_VLAN|g" \
    -e "s|@@IPXE_INTF@@|$IPXE_INTF|g" \
    $REDFISH_ROOT/boot.ipxe.template > $IPXE_ROOT/boot.ipxe
if [ ! -f "$IPXE_ROOT/boot.ipxe" ]; then
    echo "ERROR:  failed creating script [$IPXE_ROOT/boot.ipxe]"
    exit 1
fi

## BUILD IPXE
rm -f $IPXE_ROOT/src/bin-x86_64-efi/ipxe.efi
echo "Building ipxe from [$IPXE_ROOT/src] with embeded script [$IPXE_ROOT/boot.ipxe]"
make -C $IPXE_ROOT/src bin-x86_64-efi/ipxe.efi EMBED=$IPXE_ROOT/boot.ipxe 2>&1 | grep -v "[DEPS]"| sed -e "s/^/    /g"
if [ ! -f "$IPXE_ROOT/src/bin-x86_64-efi/ipxe.efi" ]; then
    echo "ERROR:  failed creating ipxe.efi [$IPXE_ROOT/src/bin-x86_64-efi/ipxe.efi]"
    exit 1
fi

## COPY IPXE TO WEB ROOT
cp -f $IPXE_ROOT/src/bin-x86_64-efi/ipxe.efi $WEB_ROOT/ipxe-$IPXE_INTF-$IPXE_VLAN.efi

echo "Created ipxe file [$WEB_ROOT/ipxe-$IPXE_INTF-$IPXE_VLAN.efi] in web root [$WEB_ROOT]"


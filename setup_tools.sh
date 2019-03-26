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
# Script to download tools for build.
#
# usage:  ./setup_tools.sh [--help]
#

# Define Variables
#

# PROCESS COMMAND LINE ARGUMENTS
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --help)
    echo "usage:  ./setup_tools.sh [--help]"
    exit 0
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# SKIP IF TOOLS HAVE ALREADY BEEN SETUP
if [ -n "$REDFISH_TOOLS_SETUP" ]; then
    exit 0
fi

# LOAD BUILD DEFAULT VALUES IF BUILD VARIABLES ARE NOT LOADED
if [ -z "$AKRAINO_ROOT" ]; then
    BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    if [ -z "$BASEDIR" ] || ! [ -f "$BASEDIR/buildrc" ]; then
        echo "ERROR:  Invalid or missing build variables rcfile [$BASEDIR/buildrc]"
        exit 1
    fi
    source "$BASEDIR/buildrc"
fi

# CHECK A FEW REQUIRED VARIABLES
if [ -z "$WEB_ROOT" ] || [ -z "$DHCP_ROOT" ] || [ -z "$REDFISH_ROOT" ] || [ -z "$DELL_ROOT" ] || [ -z "$BUILD_ROOT" ]; then
    echo "ERROR:  Invalid or missing variables in rcfile [$BASEDIR/buildrc]"
    exit 1
fi

## MAKE DIRECTORIES
mkdir -p $WEB_ROOT
mkdir -p $DHCP_ROOT
mkdir -p $BUILD_ROOT

## CHECK THAT REQUIRED PACKAGES ARE INSTALLED
echo "Checking for known required packages"
PACKAGES="docker python xorriso sshpass python-requests python-pip python-yaml python-jinja2 make gcc coreutils"
for PKG in $PACKAGES ; do
    if ! apt list $PKG 2>/dev/null | grep "$PKG.*installed.*" ; then
        echo "Attempting to install missing package $PKG"
        if ! apt-get install -y $PKG; then
            echo "FAILED:  required package $PKG not found.  try sudo 'apt-get install $PKG -y'"
            exit 1
        fi
    fi
done

## DOWNLOAD TOOLS TO REDFISH_ROOT IF TOOLS FOLDER MISSING
if [ ! -d "$REDFISH_ROOT" ]; then
    echo "Installing latest tools from [$REDFISH_REPO] to [$REDFISH_ROOT]"
    mkdir -p $REDFISH_ROOT
    curl -L "$REDFISH_REPO" | tar -xzo -C $REDFISH_ROOT 
fi
if [ ! -f "$REDFISH_ROOT/boot.ipxe.template" ]; then
    echo "ERROR:  failed cloning tools from [$REDFISH_GIT] to [$REDFISH_ROOT]"
    exit 1
fi

## DOWNLOAD DELL REDFISH REDFISH_ROOT IF DELL FOLDER MISSING
if [ ! -d "$DELL_ROOT" ]; then
    echo "Cloning Dell redfish source from [$DELL_GIT] to [$DELL_ROOT]"
    git clone $DELL_GIT $DELL_ROOT

    if [ -n "DELL_GIT_COMMIT" ]; then
        echo "Using specific commit id [$DELL_GIT_COMMIT]"
        (cd $DELL_ROOT; git checkout $DELL_GIT_COMMIT)
    fi

    ## PATCH STATUS REPORTING DELAY TO 15 SECS (INSTEAD OF 3)
    sed -i -e 's/time.sleep(3)/time.sleep(15)/g' "$DELL_ROOT/Redfish Python/ImportSystemConfigurationLocalFilenameREDFISH.py"
fi
if [ ! -f "$DELL_ROOT/Redfish Python/ImportSystemConfigurationLocalFilenameREDFISH.py" ]; then
    echo "ERROR:  failed cloning Dell redfish tools from [$DELL_GIT] to [$DELL_ROOT]"
    exit 1
fi

## DOWNLOAD HPE REDFISH REDFISH_ROOT IF HPE FOLDER MISSING
if [ ! -d "$HPE_ROOT" ]; then
    echo "Cloning HPE redfish tools from [$HPE_GIT] to [$HPE_ROOT]"
    git clone $HPE_GIT $HPE_ROOT

    ## BUILD HPE TOOLS
    (
    cd $HPE_ROOT
    python -u setup.py sdist --formats=zip
    pip install $HPE_ROOT/dist/python-ilorest-library-*.zip
    )
fi
if [ ! -f "$HPE_ROOT/examples/Redfish/_redfishobject.py" ]; then
    echo "ERROR:  failed cloning HPE redfish tools from [$HPE_GIT] to [$HPE_ROOT]"
    exit 1
fi

echo "Tools are ready in [$AKRAINO_ROOT]"
export REDFISH_TOOLS_SETUP="True"

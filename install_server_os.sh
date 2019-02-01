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
# Script to install region server.
#
# usage:  ./install_regionserver.sh  [--rc settingsfile] [--no-confirm] [--no-apply-hw] [--help]

# Define Variables
#
# NOTE: User will need to set up the required environment variables
# before executing this script if they differ from the default values.

# SET DEFAULT VALUES
UBUNTU_ISO=${UBUNTU_ISO:-}  ## IF NOT SET, UBUNTU_URL WILL BE USED TO DOWNLOAD DEFAULT ISO

# SETUP LOGGING FOR INTERACTIVE SHELLS (SAVE ORIGINAL STDIN AND STDOUT AS FD 3 AND 4)
MYLOGFILE="`basename $0`"; MYLOGFILE="${MYLOGFILE%.*}-`date +%FT%H-%M-%S-%2N`.log"
if [[ $- = *i* ]]; then
    exec 3>&1 4>&2 1> >(tee -a "$MYLOGFILE") 2>&1
    echo "Logging to $PWD/$MYLOGFILE"
fi

echo "Beginning $0 as user [$USER] in pwd [$PWD] with home [$HOME]"

# default behavior will require confirmation before starting
NO_CONFIRM=${NO_CONFIRM:-}
NO_APPLY_HW=${NO_APPLY_HW:-}
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
    --no-confirm|--skip-confirm)
    NO_CONFIRM=TRUE
    shift # past argument
    ;;
    --no-apply-hw|--skip-biosraid)
    echo "WARNING:  This run will only create the server files and not apply BIOS and RAID configuration.  This is for testing only."
    NO_APPLY_HW=TRUE
    shift # past argument
    ;;
    --help)
    echo "usage:  ./install_regionserver.sh  [--rc settingsfile] [--no-confirm] [--no-apply-hw] [--help]"
    exit 0
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# MAKE VARIABLES AVAILABLE TO OTHER TOOLS CALLED BY THIS SCRIPT
export NO_CONFIRM;
export NO_APPLY_HW;
export RCFILE;

# SETUP TOOLS AND LOAD DEFAULT BUILD VARIABLES
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $BASEDIR/setup_tools.sh 1>&2

# LOAD SERVER VARIABLES IF SERVER RCFILE PROVIDED - OTHERWISE ASSUME THE VARIABLES HAVE BEEN EXPORTED
if [ -n "$RCFILE" ] && [ -f "$RCFILE" ]; then
    source $RCFILE
fi

# CHECK A FEW REQUIRED VARIABLES - BUT NOT ALL
CHECKLIST="SRV_NAME SRV_OOB_IP SRV_OOB_USR SRV_OOB_PWD SRV_IPXE_INF BUILD_WEBPORT"
for VAR in $CHECKLIST; do
    if [ -z "${!VAR}" ] ; then
        echo "ERROR:  Invalid or missing variable [$VAR] = [${!VAR}] in rcfile [$RCFILE]"
        echo "usage:  ./install_regionserver.sh  [--rc settingsfile] [--no-confirm] [--no-apply-hw] [--help]"
        exit 1
    fi
done

## FIND BUILD_WEBIP IF NOT PROVIDED
if [ -z "$BUILD_WEBIP" ]; then
    BUILD_WEBIP=$(ip route get $SRV_IP | grep -o "src .*$" | cut -f 2 -d ' ')
    echo "Using Build Web ip address [$BUILD_WEBIP]"
fi

# SET ADDITIONAL VARIABLES BASED ON RC FILE
IPXE_VLAN=$SRV_VLAN
IPXE_INTF=$SRV_IPXE_INF
IPXE_URL=http://$BUILD_WEBIP:$BUILD_WEBPORT/ipxe-$SRV_IPXE_INF-$SRV_VLAN.efi
SRV_FIRSTBOOT_TEMPLATE=${SRV_FIRSTBOOT_TEMPLATE:-firstboot.sh.template}

if [ -z "$NO_CONFIRM" ]; then
    echo ""
    read -r -p "Preparing to build of server [$SRV_NAME] using oob ip [$SRV_OOB_IP].  Are you sure? [y/N] " response
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
    echo -n "WARNING:  Preparing to build server [$SRV_NAME] using oob ip [$SRV_OOB_IP].  Beginning in $i seconds "
    while [ $i -gt 0 ]; do
        echo -n "."; sleep 1; i=$[$i-1]
    done
    echo ""
fi

echo "Beginning bare metal install of os at" `date`
STARTTIME=$(date +%s)

## CHECK THAT DOCKER EXISTS
VERSION=$(docker --version)
if [ $? -ne 0 ] || [ -z "$VERSION" ]; then
    echo "ERROR: Unable to determine docker version [$VERSION]"
    exit 1;
fi

## CHECK IF BUILD_WEBIP IS ON THIS SERVER
if ! ifconfig | grep -B1 ":$BUILD_WEBIP " >/dev/null; then
    echo "ERROR:  Build Web ip address [$BUILD_WEBIP] not found on this server"
    ifconfig | grep --no-group-separator -B1 "inet addr:"
    exit 1
else
    echo "Found build web ip address [$BUILD_WEBIP] on this server!"
    ifconfig | grep --no-group-separator -B1 ":$BUILD_WEBIP "
fi

## COLLECT ANY ADDITIONAL SERVER DATA NEEDED - FOR EXAMPLE, LOOKUP MAC FOR DELL NIC
case $SRV_OEM in
    Dell|DELL)
    if [ -z "$SRV_MAC" ]; then
        SRV_MAC=$(. $TOOLS_ROOT/get_dellnicmac.sh --nic $SRV_HTTP_BOOT_DEV)
        if [ "$?" -ne 0 ]; then
            echo "ERROR:  Unable to get Dell nic mac address from [$SRV_OOB_IP]"
            exit 1;
        fi
    fi
    ;;
    HP|HPE)
    if [ -z "$SRV_MAC" ]; then
        echo "ERROR:  HPE required variable SRV_MAC missing from rc file [$RCFILE]"
        exit 1;
    fi
    ;;
    *)    # unknown option
    echo "ERROR:  Unknown server oem [$SRV_OEM]"
    exit 1;
    ;;
esac

## UPDATE WEB ROOT WITH UBUNTU ISO
. $TOOLS_ROOT/update_webroot.sh;
if [ "$?" -ne 0 ]; then
    echo "ERROR:  failed to add [$UBUNTU_ISO] contents to web root"
    exit 1
fi

## CREATE IPXE FILE
echo "Creating ixpe.efi for web root in folder [$WEB_ROOT] using interface [$SRV_IPXE_INF] and vlan [$SRV_VLAN]"
if ! (IPXE_VLAN=$SRV_VLAN IPXE_INTF=$SRV_IPXE_INF $TOOLS_ROOT/create_ipxe.sh); then
    echo "ERROR:  failed to add ipxe file to web root"
    exit 1
fi

## ADD FIRSTBOOT SCRIPT TO WEB ROOT
echo "Adding firstboot script [$SRV_NAME.firstboot.sh] to web root [$WEB_ROOT]"
cp -f $TOOLS_ROOT/$SRV_FIRSTBOOT_TEMPLATE $WEB_ROOT/$SRV_NAME.firstboot.sh

for VAR in $(set | grep -P "^SRV_|^BUILD_" | cut -f 1 -d'='); do
    sed -i -e "s|@@$VAR@@|${!VAR}|g" $WEB_ROOT/$SRV_NAME.firstboot.sh
done

## CHECK THAT ALL VALUES WERE REPLACED
MISSING=$(grep -Po "@@.*?@@" $WEB_ROOT/$SRV_NAME.firstboot.sh | sort | uniq)
if [ -n "$MISSING" ] ; then
    echo "ERROR:  Required variable(s) in template [$SRV_FIRSTBOOT_TEMPLATE] were not located in the resource file [$RCFILE]"
    echo ${MISSING//@@/} | xargs -n 1 | sed -e 's/^/        /g'
    exit 1
fi

## CREATE SERVER SEED FILE
echo "Creating seed file [$WEB_ROOT/$SRV_NAME.seed] for server [$SRV_NAME]"
cp -f $TOOLS_ROOT/ubuntu.seed.template $WEB_ROOT/$SRV_NAME.seed

for VAR in $(set | grep -P "^SRV_|^BUILD_" | cut -f 1 -d'='); do
    sed -i -e "s|@@$VAR@@|${!VAR}|g" $WEB_ROOT/$SRV_NAME.seed
done

## CHECK THAT ALL VALUES WERE REPLACED
MISSING=$(grep -Po "@@.*?@@" $WEB_ROOT/$SRV_NAME.seed | sort | uniq)
if [ -n "$MISSING" ] ; then
    echo "ERROR:  Required variable(s) in template [ubuntu.seed.template] were not located in the resource file [$RCFILE]"
    echo ${MISSING//@@/} | xargs -n 1 | sed -e 's/^/        /g'
    exit 1
fi

## START WEB SERVICE
echo "Starting web server using folder [$WEB_ROOT] on port [$BUILD_WEBPORT]"
# existing container is using different web root or does not exist
docker stop akraino-httpboot &> /dev/null
docker rm akraino-httpboot &> /dev/null
docker run -dit --name akraino-httpboot -p $BUILD_WEBPORT:80 -v "$WEB_ROOT":/usr/local/apache2/htdocs/ httpd:alpine >/dev/null && sleep 5
if ! docker ps | grep akraino-httpboot >/dev/null || ! curl http://localhost:$BUILD_WEBPORT/ &>/dev/null ; then
    echo "ERROR: Failed to start web server using folder [$WEB_ROOT] and port [$BUILD_WEBPORT]"
    ls -l $WEB_ROOT
    docker run -it --name akraino-httpboot -p $BUILD_WEBPORT:80 -v "$WEB_ROOT":/usr/local/apache2/htdocs/ httpd:alpine 2>&1
    exit 1
fi

## CREATE DHCP CONFIG FILE
if [ ! -f "$DHCP_ROOT/dhcpd.conf" ]; then
    echo "Creating new dhcp configuration [$DHCP_ROOT/dhcpd.conf]"
    mkdir -p $DHCP_ROOT
    cp -f $TOOLS_ROOT/dhcpd.conf.template $DHCP_ROOT/dhcpd.conf
fi

SRV_DNSCSV=$(echo $SRV_DNS | tr ' ' ',')
echo "Updating dhcp configuration [$DHCP_ROOT/dhcpd.conf] with subnet [$SRV_SUBNET]"
perl -i -p0e "s/^subnet $SRV_SUBNET .*?\n\}\n//gms" $DHCP_ROOT/dhcpd.conf
cat >>$DHCP_ROOT/dhcpd.conf <<EOF
subnet $SRV_SUBNET netmask $SRV_NETMASK {
    option subnet-mask $SRV_NETMASK;
    option routers $SRV_GATEWAY;
    option domain-name-servers $SRV_DNSCSV;
    option domain-name "$SRV_DOMAIN";
    option ipxe-web-server "$BUILD_WEBIP:$BUILD_WEBPORT";
}
EOF

## CHECK THAT SRV_BLD_SCRIPT EXISTS
if [ ! -f "$WEB_ROOT/$SRV_BLD_SCRIPT" ]; then
    echo "ERROR: Missing SRV_BLD_SCRIPT [$SRV_BLD_SCRIPT] from web root [$WEB_ROOT]"
    exit 1
fi

echo "Updating dhcp configuration [$DHCP_ROOT/dhcpd.conf] with server [$SRV_NAME]"
## DELETE ANY HOST ENTRY WITH THE SAME MAC ADDRESS OR NAME
perl -i -p0e "s/^host.*?$SRV_MAC.*?\n\}\n//gms" $DHCP_ROOT/dhcpd.conf
perl -i -p0e "s/^host *$SRV_NAME *{.*?\n\}\n//gms" $DHCP_ROOT/dhcpd.conf
cat >>$DHCP_ROOT/dhcpd.conf <<EOF
host $SRV_NAME {
    hardware ethernet $SRV_MAC;
    fixed-address $SRV_IP;
    option host-name $SRV_NAME;
    option ipxe-interface "$SRV_BLD_INF";
    if substring (option vendor-class-identifier,0,9) = "PXEClient" {
        filename "http://$BUILD_WEBIP:$BUILD_WEBPORT/$SRV_BLD_SCRIPT";
    }
}
EOF

## START/RESTART DHCP SERVICE
echo "Starting dhcp server using folder [$DHCP_ROOT] on interface [$BUILD_INTERFACE]"
docker stop akraino-dhcp &> /dev/null
docker rm akraino-dhcp &> /dev/null
docker run -dit --name akraino-dhcp --rm --net=host -v "$DHCP_ROOT":/data networkboot/dhcpd $BUILD_INTERFACE >/dev/null && sleep 5
if ! docker ps | grep akraino-dhcp >/dev/null; then
    echo "ERROR: Failed to start dhcp server using folder [$DHCP_ROOT] and interface [$BUILD_INTERFACE]"
    echo "Contents of [$DHCP_ROOT/dhcpd.conf]"
    cat $DHCP_ROOT/dhcpd.conf
    docker run -it --name akraino-dhcp --rm --net=host -v "$DHCP_ROOT":/data networkboot/dhcpd $BUILD_INTERFACE 2>&1
    exit 1
fi

## CREATE CONFIG FILES AND APPLY UNLESS CALLED WITH --no-apply-hw
case $SRV_OEM in
    Dell|DELL)
        if [ -n "$SRV_BIOS_TEMPLATE" ]; then
            . $TOOLS_ROOT/apply_dellxml.sh --template $SRV_BIOS_TEMPLATE
            echo "Completed update with status [$?]"
            sleep 80
        fi

        if [ -n "$SRV_BOOT_TEMPLATE" ]; then
            . $TOOLS_ROOT/apply_dellxml.sh --template $SRV_BOOT_TEMPLATE
            echo "Completed update with status [$?]"
            sleep 20
        fi
    ;;
    HP|HPE)
        if [ -n "$SRV_BIOS_TEMPLATE" ]; then
            . $TOOLS_ROOT/apply_hpejson.sh --template $SRV_BIOS_TEMPLATE
            echo "Completed update with status [$?]"
        fi
        if [ -n "$SRV_BOOT_TEMPLATE" ]; then
            . $TOOLS_ROOT/apply_hpejson.sh --template $SRV_BOOT_TEMPLATE
            echo "Completed update with status [$?]"
            echo "Waiting for server to reboot with new settings."
        fi
    ;;
    *)  # unknown option
        echo "ERROR:  Unknown server oem [$SRV_OEM]"
        exit 1;
    ;;
esac

if [ -z "$NO_APPLY_HW" ]; then

    ## WAIT FOR UBUNTU INSTALL TO DOWNLOAD $SRV_NAME.firstboot.sh
    echo "Waiting for server [$SRV_IP] to download [$SRV_NAME.firstboot.sh] from web container at" `date`
    echo "This step could take up to 15 minutes"
    WEBLOG_START=$(date +%FT%T)
    WSTART=$(date +%s)
    # ONLY CHECK ENTRIES AFTER WEBLOG_START TO AVOID PAST BUILDS, CHECK UP TO LAST 10 ENTRIES TO AVOID MISSING MESSAGES AFTER RESTART
    while [ $(date +%s) -lt $[$WSTART + 900] ] && ( ! (timeout 900s docker logs --since "$WEBLOG_START" --tail 10 -f akraino-httpboot &) | awk "{print \$0; fflush();} /^$SRV_IP.*GET \/$SRV_NAME.firstboot.sh/ {exit;}" ); do
        echo "WARNING:  Web server was restarted..."
    done

    if [ $(date +%s) -gt $[$WSTART + 900] ]; then
        echo "ERROR:  Timeout waiting for server to download firstboot.sh"
        exit 1
    fi

    ## WAIT FOR SERVER TO START REBOOT
    echo "Waiting for server [$SRV_IP] to reboot" `date`
    echo "Waiting for server to shutdown..."
    (ping -i 5 $SRV_IP &) | awk '{print $0; fflush();} /Destination Host Unreachable/ {x++; if (x>3) {exit;}}'

    # wait for previous ping to abort
    sleep 10
else
    ## SKIPPING REBOOT
    echo "Skipping application of BIOS/RAID settings - OS should be installed already to work properly - normally used for testing only"
fi

## WAIT FOR SERVER TO FINISH REBOOT - PING SUCCEEDS 4 TIMES
echo "Waiting for server to come back up..."
(ping -i 5 $SRV_IP &) | awk '{print $0; fflush();} /time=/ {x++; if (x>3) {exit;}}'

## SETUP SSH KEYS
echo "Setting up ssh keys for user [$USER] with home [$HOME]"
if ! dpkg -l | grep "sshpass " > /dev/null; then
    echo "  Installing sshpass"
    apt-get install -y sshpass 2>&1 || echo "ERROR: sshpass is required to complete the build"; exit 1;
fi
if ! [ -f $HOME/.ssh/id_rsa ]; then
    echo "  Creating rsa key [$HOME/.ssh/id_rsa]"
    ssh-keygen -t rsa -f $HOME/.ssh/id_rsa -P ""
fi
echo "  Removing any old host keys for [$SRV_IP]"
ls -l $HOME/.ssh/
chown $USER:$USER $HOME/.ssh/known_hosts
ssh-keygen -f "$HOME/.ssh/known_hosts" -R $SRV_IP
chown $USER:$USER $HOME/.ssh/known_hosts
ls -l $HOME/.ssh/

echo "  Getting new host keys for [$SRV_IP]"
sleep 5
ssh-keyscan -t rsa -H $SRV_IP >> $HOME/.ssh/known_hosts

echo "  copying user key to [root@$SRV_IP]"
sleep 5
export SSHPASS=$SRV_PWD
sshpass -e ssh-copy-id -i $HOME/.ssh/id_rsa root@$SRV_IP

## RUN FIRSTBOOT SCRIPT
echo "Running first boot script"
sleep 5
sshpass -e ssh -i $HOME/.ssh/id_rsa root@$SRV_IP /root/$SRV_NAME.firstboot.sh
if [ "$?" -ne 0 ]; then
    echo "FAILED:  Unable to run firstboot script on new server"
    exit 1
fi

## DELETE HOST ENTRY FROM DHCP
echo "Removing dhcp configuration for server [$SRV_NAME] [$SRV_MAC] from [$DHCP_ROOT/dhcpd.conf]"
perl -i -p0e "s/^host.*?$SRV_MAC.*?\n\}\n//gms" $DHCP_ROOT/dhcpd.conf
perl -i -p0e "s/^host *$SRV_NAME *{.*?\n\}\n//gms" $DHCP_ROOT/dhcpd.conf

## RESTART DHCP SERVICE
echo "Restarting dhcp server using folder [$DHCP_ROOT] on interface [$BUILD_INTERFACE]"
docker restart akraino-dhcp &> /dev/null

## DONE
ENDTIME=$(date +%s)
echo "SUCCESS:  Completed bare metal install of regional server [$SRV_NAME] at" `date`
echo "SUCCESS:  Try connecting with 'ssh root@$SRV_IP' as user $USER"
echo "Elapsed time was $(( ($ENDTIME - $STARTTIME) / 60 )) minutes and $(( ($ENDTIME - $STARTTIME) % 60 )) seconds"

## RESTORE SAVED STDIN AND STDOUT (TERMINATES TEE REDIRECTION)
if [[ $- = *i* ]]; then
    exec 1>&3 2>&4
fi
exit 0


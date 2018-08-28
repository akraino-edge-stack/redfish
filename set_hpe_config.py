#!/usr/bin/python
 #Copyright 2016 Hewlett Packard Enterprise Development LP
 #
 # Licensed under the Apache License, Version 2.0 (the "License"); you may
 # not use this file except in compliance with the License. You may obtain
 # a copy of the License at
 #
 #      http://www.apache.org/licenses/LICENSE-2.0
 #
 # Unless required by applicable law or agreed to in writing, software
 # distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 # WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 # License for the specific language governing permissions and limitations
 # under the License.

import sys, os, argparse, json
from _redfishobject import RedfishObject
from redfish.rest.v1 import ServerDownOrUnreachableError

parser = argparse.ArgumentParser(description='Python script using Redfish API to update all BIOS attributes')
parser.add_argument('-ip', help='iLO IP address', required=True)
parser.add_argument('-u', help='iLO username', required=True)
parser.add_argument('-p', help='iLO password', required=True)
parser.add_argument('-f', help='Input File', required=True)

args = vars(parser.parse_args())


## Create Logical Drives #########

def create_logical_drive (redfishobj, inputfile):
    sys.stdout.write("\nCreating Logical Drives in HP Gen 10\n")
    instances = redfishobj.search_for_type("smartstorageconfig.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example requires the Redfish schema "\
                 "version TBD in the managed iLO. It will fail against iLOs"\
                 " with the 2.50 firmware or earlier. \n")

    for instance in instances:
        response = redfishobj.redfish_get(instance["@odata.id"])
        storage = response.dict["LogicalDrives"]
        jfile = json.loads(open(inputfile).read())
        ## TODO: Need to create the Logical Drive here
        for i in jfile:
            if "/redfish/v1/Systems/1/smartstorageconfig/settings/" in i:
                body = dict()
                body["LogicalDrives"] = i["/redfish/v1/Systems/1/smartstorageconfig/settings/"]["PATCH"]

                response = redfishobj.redfish_patch(instance["@odata.id"], body)
                redfishobj.error_handler(response)

##### Change Boot Order to NIC  ###########
def change_boot_order(redfishobj, inputfile, bios_password=None):
    sys.stdout.write("\nChange Boot Order (UEFI)\n")
    instances = redfishobj.search_for_type("ServerBootSettings.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example requires the Redfish schema "\
                 "version TBD in the managed iLO. It will fail against iLOs"\
                 " with the 2.50 firmware or earlier. \n")

    for instance in instances:
        response = redfishobj.redfish_get(instance["@odata.id"])
        bootorder = response.dict["PersistentBootConfigOrder"]

#        #TODO: Need to change the persistent boot order here
        jfile = json.loads(open(inputfile).read())
        for i in jfile:
            if "/redfish/v1/systems/1/bios/boot/settings/" in i:
                body = dict()
                body["PersistentBootConfigOrder"] = i["/redfish/v1/systems/1/bios/boot/settings/"]["PATCH"]["PersistentBootConfigOrder"]

                response = redfishobj.redfish_patch(instance["@odata.id"], body)
                redfishobj.error_handler(response)


#### Change  BIOS settings  ####
def set_bios(redfishobj, inputfile, bios_password=None):
    sys.stdout.write("\nSet BIOS  boot Mode\n")
    instances = redfishobj.search_for_type("Bios.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example requires the Redfish schema "\
                 "version TBD in the managed iLO. It will fail against iLOs"\
                 " with the 2.50 firmware or earlier.\n")

    for instance in instances:
        response = redfishobj.redfish_get(instance["@odata.id"])
        bootoptions = response.dict["Attributes"]
        jfile = json.loads(open(inputfile).read())
        for i in jfile:
            if "/redfish/v1/systems/1/bios/settings/" in i:
                body = dict()
                body["Attributes"] = i["/redfish/v1/systems/1/bios/settings/"]["PATCH"]["Attributes"]
                response = redfishobj.redfish_patch(instance["@odata.id"], body)
                redfishobj.error_handler(response)

#### Restart server #####
def reset_server(redfishobj, inputfile, bios_password=None):
    sys.stdout.write("\nReset a server\n")
    instances = redfishobj.search_for_type("ComputerSystem.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example requires the Redfish schema "\
                 "version TBD in the managed iLO. It will fail against iLOs"\
                 " with the 2.50 firmware or earlier. \n")

    for instance in instances:
        resp = redfishobj.redfish_get(instance['@odata.id'])
        if resp.status==200:
            body = dict()
            jfile = json.loads(open(inputfile).read())
            for i in jfile:
                if "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/" in i:
                    body = i["/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/"]["POST"]
#            body["Action"] = "ComputerSystem.Reset"
#            body["ResetType"] = "ForceRestart"
#            print body
            path = resp.dict["Actions"]["#ComputerSystem.Reset"]["target"]
        else:
            sys.stderr.write("ERROR: Unable to find the path for reboot.")
        response = redfishobj.redfish_post(path, body)
        redfishobj.error_handler(response)



########### This Below area changes for each server or ilo ##################
if __name__ == "__main__":

    iLO_https_url = "https://"+args['ip']
    iLO_account = args['u']
    iLO_password = args["p"]
    inputfile = args["f"]

# Create a REDFISH object ##
    try:
        REDFISH_OBJ = RedfishObject(iLO_https_url, iLO_account, iLO_password)
    except ServerDownOrUnreachableError as excp:
        sys.stderr.write("ERROR: server not reachable or doesn't support " \
                                                                "RedFish.\n")
        sys.exit()
    except Exception as excp:
        raise excp

    create_logical_drive(REDFISH_OBJ, inputfile)
    change_boot_order(REDFISH_OBJ, inputfile)
    set_bios(REDFISH_OBJ, inputfile)
    reset_server(REDFISH_OBJ, inputfile)
    REDFISH_OBJ.redfish_client.logout()


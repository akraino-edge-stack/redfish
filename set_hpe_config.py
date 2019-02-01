#!/usr/bin/python

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

import sys, os, argparse, json, time
from _redfishobject import RedfishObject
from redfish.rest.v1 import ServerDownOrUnreachableError

parser = argparse.ArgumentParser(description='Python script using Redfish API to update BIOS attributes')
parser.add_argument('-ip', help='iLO IP address', required=True)
parser.add_argument('-u', help='iLO username', required=True)
parser.add_argument('-p', help='iLO password', required=True)
parser.add_argument('-f', help='Input File', required=True)

args = vars(parser.parse_args())

##### Wait for Server State #####
def waitfor_server_state (redfishobj, get_state_func, end_state):
    timeout = time.time() + 60 * 6;
    srv_state = ""
    sys.stdout.write("Waiting for server to reach state [{0}].  Current state:".format(end_state))
    while srv_state != end_state and time.time() < timeout:
        new_state = get_state_func(redfishobj)
        if new_state != srv_state:
            sys.stdout.write("\n    "+new_state)
            srv_state = new_state
        else:
            sys.stdout.write('.')
        sys.stdout.flush()
        time.sleep(1)

    sys.stdout.write("\n")
    if get_state_func(redfishobj) != end_state:
        sys.stdout.write("Timed out waiting for server to reach state [{0}].".format(end_state))
        exit(1)

##### Get Power State #####
def get_power_state (redfishobj):
    instances = redfishobj.search_for_type("ComputerSystem.")
    if len(instances) != 1:
        sys.stderr.write("\nERROR: Unable to find ComputerSystem object\n")
        exit(1)

    response = redfishobj.redfish_get(instances[0]["@odata.id"])
    if response.status != 200:
        redfishobj.error_handler(response)
        exit(1)
    return response.dict["PowerState"]

##### Get Post State #####
def get_post_state (redfishobj):
    instances = redfishobj.search_for_type("ComputerSystem.")
    if len(instances) != 1:
        sys.stderr.write("\nERROR: Unable to find ComputerSystem object\n")
        exit(1)

    response = redfishobj.redfish_get(instances[0]["@odata.id"])
    if response.status != 200:
        redfishobj.error_handler(response)
        exit(1)
    return response.dict["Oem"]["Hpe"]["PostState"]

##### Get Logical Drives #####
def get_logical_drives (redfishobj):
    instances = redfishobj.search_for_type("smartstorageconfig.")
    if not len(instances):
        sys.stderr.write("\nERROR: Unable to find SmartStorageConfig object\n")
        exit(1)

    for instance in instances:
        if instance["@odata.id"][-10:] != "/settings/":
            response = redfishobj.redfish_get(instance["@odata.id"])
            if response.status != 200:
                redfishobj.error_handler(response)
                exit(1)
            print json.dumps(response.dict,sort_keys=True,indent=4, separators=(',', ': '))

##### Get Boot Order #####
def get_boot_order (redfishobj):
    instances = redfishobj.search_for_type("ServerBootSettings.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example will fail on HP Gen9 iLOs"\
                 " with the 2.50 firmware or earlier.\n")

    for instance in instances:
        if instance["@odata.id"][-10:] != "/settings/":
            response = redfishobj.redfish_get(instance["@odata.id"])
            if response.status != 200:
                redfishobj.error_handler(response)
                exit(1)
            print json.dumps(response.dict,sort_keys=True,indent=4, separators=(',', ': '))

##### Get BIOS settings  #####
def get_bios (redfishobj):
    instances = redfishobj.search_for_type("Bios.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example will fail on HP Gen9 iLOs"\
                 " with the 2.50 firmware or earlier.\n")

    for instance in instances:
        if instance["@odata.id"][-10:] != "/settings/":
            response = redfishobj.redfish_get(instance["@odata.id"])
            if response.status != 200:
                redfishobj.error_handler(response)
                exit(1)
            print json.dumps(response.dict,sort_keys=True,indent=4, separators=(',', ': '))

##### Set Logical Drive(s) #####
def set_logical_drive (redfishobj, data):
    instances = redfishobj.search_for_type("smartstorageconfig.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example will fail on HP Gen9 iLOs"\
                 " with the 2.50 firmware or earlier.\n")

    for instance in instances:
        if instance["@odata.id"][-10:] == "/settings/":
            response = redfishobj.redfish_get(instance["@odata.id"])
            #print json.dumps(response.dict,sort_keys=True,indent=4, separators=(',', ': '))
            #print response
            #storage = response.dict["LogicalDrives"]

            body = dict()
            body["LogicalDrives"] = data
            body["DataGuard"] = "Disabled"
            print json.dumps(body,sort_keys=True,indent=4, separators=(',', ': '))
            response = redfishobj.redfish_put(instance["@odata.id"], body)
            if response.status != 200:
                redfishobj.error_handler(response)
                #response = redfishobj.redfish_get(instance["@odata.id"])
                #print response
                exit(1)


##### Set Boot Order #####
def set_boot_order(redfishobj, data, bios_password=None):
    instances = redfishobj.search_for_type("ServerBootSettings.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example will fail on HP Gen9 iLOs"\
                 " with the 2.50 firmware or earlier.\n")

    for instance in instances:
        if instance["@odata.id"][-10:] == "/settings/":
            response = redfishobj.redfish_get(instance["@odata.id"])
            body = data
            response = redfishobj.redfish_patch(instance["@odata.id"], body)
            if response.status != 200:
                redfishobj.error_handler(response)
                exit(1)

##### Set BIOS settings  #####
def set_bios(redfishobj, data, bios_password=None):
    instances = redfishobj.search_for_type("Bios.")
    if not len(instances) and redfishobj.typepath.defs.isgen9:
        sys.stderr.write("\nNOTE: This example will fail on HP Gen9 iLOs"\
                 " with the 2.50 firmware or earlier.\n")

    for instance in instances:
        if instance["@odata.id"][-10:] == "/settings/":
            response = redfishobj.redfish_get(instance["@odata.id"])
            body = data
            response = redfishobj.redfish_patch(instance["@odata.id"], body)
            if response.status != 200:
                redfishobj.error_handler(response)
                exit(1)

##### Reset server #####
def reset_server(redfishobj, data, bios_password=None):
    ## common reset types: On, ForceOff, ForceRestart ##
    instances = redfishobj.search_for_type("ComputerSystem.")
    if len(instances) != 1:
        sys.stderr.write("\nERROR: Unable to find ComputerSystem object\n")
        exit(1)

    resp = redfishobj.redfish_get(instances[0]["@odata.id"])
    if resp.status==200:
        body = data
        path = resp.dict["Actions"]["#ComputerSystem.Reset"]["target"]
    else:
        sys.stderr.write("ERROR: Unable to find the path for reboot.")
        exit(1)
    if body["ResetType"] == "ForceOff":
        if  get_power_state(redfishobj) != "Off":
            response = redfishobj.redfish_post(path, body)
            if response.status != 200:
                redfishobj.error_handler(response)
                exit(1)
        waitfor_server_state(redfishobj, get_power_state, "Off")

    elif body["ResetType"] == "On":
        if  get_power_state(redfishobj) == "Off":
            response = redfishobj.redfish_post(path, body)
            if response.status != 200:
                redfishobj.error_handler(response)
                exit(1)
        waitfor_server_state(redfishobj, get_post_state, "InPostDiscoveryComplete")

    elif body["ResetType"] == "ForceRestart":
        if get_power_state(redfishobj) == "Off":
            body["ResetType"] = "On"
        response = redfishobj.redfish_post(path, body)
        if response.status != 200:
            redfishobj.error_handler(response)
            exit(1)
        waitfor_server_state(redfishobj, get_post_state, "InPost")
        waitfor_server_state(redfishobj, get_post_state, "InPostDiscoveryComplete")
    else:
        print "ERROR:  Unhandled reset type {0}".format(body["ResetType"])

########### This area changes for each server or ilo ###########
if __name__ == "__main__":

    iLO_https_url = "https://"+args['ip']
    iLO_account = args['u']
    iLO_password = args["p"]
    inputfile = args["f"]

    ## Create REDFISH object ##
    try:
        REDFISH_OBJ = RedfishObject(iLO_https_url, iLO_account, iLO_password)
    except ServerDownOrUnreachableError as excp:
        sys.stderr.write("ERROR: server not reachable or doesn't support RedFish.\n")
        sys.exit()
    except Exception as excp:
        raise excp

    ## Process changes in input file ##
    jfile = json.loads(open(inputfile).read())
    print "### Found {0} tasks to be completed in file {1}".format(len(jfile), inputfile)
    for i in jfile:
        for rf_path, v in i.items():
            for rf_method, rf_data in v.items():
                print "###"
                print "### BEGIN TASK"
                print "###"
                if rf_path == "/redfish/v1/Systems/1/smartstorageconfig/settings/":
                    print "Creating logical drives"
                    set_logical_drive(REDFISH_OBJ, rf_data)
                elif rf_path == "/redfish/v1/systems/1/bios/settings/":
                    print "Applying BIOS settings"
                    set_bios(REDFISH_OBJ, rf_data)
                elif rf_path == "/redfish/v1/systems/1/bios/boot/settings/":
                    print "Updating boot order"
                    set_boot_order(REDFISH_OBJ, rf_data)
                elif rf_path == "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/":
                    print "Setting server state to {0}".format(rf_data["ResetType"])
                    reset_server(REDFISH_OBJ, rf_data)
                else:
                    print "WARNING: Ignoring unknown redfish path {0}.".format(rf_path)
                    continue

    ## Print final state ##
    print "###"
    print "### FINAL BIOS SETTINGS"
    print "###"
    get_bios(REDFISH_OBJ)
    print "###"
    print "### FINAL BOOT SETTINGS"
    print "###"
    get_boot_order(REDFISH_OBJ)
    print "###"
    print "### FINAL SMART ARRAY SETTINGS"
    print "###"
    get_logical_drives(REDFISH_OBJ)
    print "Server power state: {0}".format(get_power_state(REDFISH_OBJ))
    print "Server POST state: {0}".format(get_post_state(REDFISH_OBJ))

    REDFISH_OBJ.redfish_client.logout()


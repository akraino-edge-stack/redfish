#!/bin/bash
#
# Copyright (c) 2018 AT&T Intellectual Property.  All other rights reserved.
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

#Pass version number as argument to run script:
#example : ./build.sh 1.0.0-SNAPSHOT
#DOCKER_REPO='nexus3.akraino.org:10003'

set -e -u -x -o pipefail

echo '---> Starting build-docker'

CON_NAME="akraino-redfish"
VERSION=`cat version.properties | grep VERSION |cut -d '=' -f 2`

docker build -f Dockerfile --rm -t ${CON_NAME}:${VERSION} .
docker tag ${CON_NAME}:${VERSION} ${DOCKER_REPO}/${CON_NAME}:${VERSION}
docker push ${DOCKER_REPO}/${CON_NAME}:${VERSION}


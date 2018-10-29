##############################################################################
# Copyright (c) 2018 AT&T Intellectual Property. All rights reserved.        #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License.                   #
#                                                                            #
# You may obtain a copy of the License at                                    #
#       http://www.apache.org/licenses/LICENSE-2.0                           #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT  #
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.           #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
##############################################################################
FROM ubuntu:16.04
#
USER root
#Install Dependency
RUN \
  apt-get update && \
  apt-get install -y  python python-dev python-pip && \
  apt-get install -y sshpass python-requests xorriso coreutils && \
  apt-get install -y apt-transport-https aufs-tools docker.io curl iputils-ping net-tools vim

# Create and Define working directory.
RUN \
  mkdir -p /opt/tools && \
  mkdir -p /op/dell && \
  mkdir -p /opt/hpe && \
  mkdir -p /opt/akraino  

# Setting up environemnt
ARG DELL_GIT=https://github.com/dell/iDRAC-Redfish-Scripting.git
ARG HPE_GIT=https://github.com/HewlettPackard/python-ilorest-library.git
ARG DELL_GIT_COMMIT=64f184c8c37ed1f64831c5695cd69092105e5eec
ENV DELL_ROOT=/opt/dell
ENV HPE_ROOT=/opt/hpe
ARG NEXUS_URL=https://nexus.akraino.org
ARG PROJECT=redfish
ARG VERSION=0.0.2-SNAPSHOT
ARG V2=0.0.2-20181014.034005-6
ENV XMLFILE=$NEXUS_URL/service/local/repositories/snapshots/content/org/akraino/${PROJECT}/${PROJECT}/${VERSION}/maven-metadata.xml

RUN curl -O $XMLFILE && \
  echo $XMLFILE && \
  ls -la

ENV TGZFILE=$NEXUS_URL/service/local/repositories/snapshots/content/org/akraino/$PROJECT/$PROJECT/$VERSION/$PROJECT-$V2.tgz

RUN echo $TGZFILE && \
 ## Downloading the latest redfish artifact from LFNexus
  curl -O $TGZFILE && \
  ls -la && \
  tar -xzvf $PROJECT-$V2.tgz -C /opt/tools

 ## Setup DELL and HP packages
RUN \
  git clone $DELL_GIT $DELL_ROOT && \
  cd $DELL_ROOT && git checkout $DELL_GIT_COMMIT && \
  ## PATCH STATUS REPORTING DELAY TO 15 SECS (INSTEAD OF 3)
  sed -i -e 's/time.sleep(3)/time.sleep(15)/g' "$DELL_ROOT/Redfish Python/ImportSystemConfigurationLocalFilenameREDFISH.py"

RUN \
  git clone $HPE_GIT $HPE_ROOT && \
  cd $HPE_ROOT && python -u setup.py sdist --formats=zip && \
  pip install $HPE_ROOT/dist/python-ilorest-library-*.zip

CMD ["/bin/bash"]



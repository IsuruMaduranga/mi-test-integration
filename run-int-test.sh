#!/bin/bash
#----------------------------------------------------------------------------
#  Copyright (c) 2022 WSO2, LLC. http://www.wso2.org
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#----------------------------------------------------------------------------
set -o xtrace; set -e

TESTGRID_DIR=/opt/testgrid/workspace
INFRA_JSON='infra.json'

PRODUCT_REPOSITORY=$1
PRODUCT_REPOSITORY_BRANCH=$2
PRODUCT_NAME=$3
PRODUCT_VERSION=$4
GIT_USER=$5
GIT_PASS=$6
TEST_MODE=$7
PRODUCT_REPOSITORY_NAME=$(echo $PRODUCT_REPOSITORY | rev | cut -d'/' -f1 | rev | cut -d'.' -f1)
PRODUCT_REPOSITORY_PACK_DIR="$TESTGRID_DIR/$PRODUCT_REPOSITORY_NAME/distribution/target"
INT_TEST_MODULE_DIR="$TESTGRID_DIR/$PRODUCT_REPOSITORY_NAME/integration"

# CloudFormation properties
CFN_PROP_FILE="${TESTGRID_DIR}/cfn-props.properties"

JDK_TYPE=$(grep -w "JDK_TYPE" ${CFN_PROP_FILE} | cut -d"=" -f2)
PRODUCT_PACK_NAME=$(grep -w "REMOTE_PACK_NAME" ${CFN_PROP_FILE} | cut -d"=" -f2)

function log_info(){
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
}

function log_error(){
    echo "[ERROR][$(date '+%Y-%m-%d %H:%M:%S')]: $1"
    exit 1
}

function install_jdk(){
    jdk_name=$1

    mkdir -p /opt/${jdk_name}
    jdk_file=$(jq -r '.jdk[] | select ( .name == '\"${jdk_name}\"') | .file_name' ${INFRA_JSON})
    wget -q https://integration-testgrid-resources.s3.amazonaws.com/lib/jdk/$jdk_file.tar.gz
    tar -xzf "$jdk_file.tar.gz" -C /opt/${jdk_name} --strip-component=1

    export JAVA_HOME=/opt/${jdk_name}
    echo $JAVA_HOME
}

source /etc/environment

log_info "Clone Product repository"
git clone https://${GIT_USER}:${GIT_PASS}@$PRODUCT_REPOSITORY --branch $PRODUCT_REPOSITORY_BRANCH --single-branch

log_info "Exporting JDK"
install_jdk ${JDK_TYPE}

mkdir -p $PRODUCT_REPOSITORY_PACK_DIR
log_info "Copying product pack to Repository"
[ -f $TESTGRID_DIR/$PRODUCT_NAME-$PRODUCT_VERSION*.zip ] && rm -f $TESTGRID_DIR/$PRODUCT_NAME-$PRODUCT_VERSION*.zip
cd $TESTGRID_DIR && zip -qr $PRODUCT_PACK_NAME.zip $PRODUCT_PACK_NAME
mv $TESTGRID_DIR/$PRODUCT_PACK_NAME.zip $PRODUCT_REPOSITORY_PACK_DIR/.
log_info "install pack into local maven Repository"
mvn install:install-file -Dfile=$PRODUCT_REPOSITORY_PACK_DIR/$PRODUCT_PACK_NAME.zip -DgroupId=org.wso2.am -DartifactId=wso2am -Dversion=$PRODUCT_VERSION -Dpackaging=zip --file=$PRODUCT_REPOSITORY_PACK_DIR/../pom.xml 
cd $INT_TEST_MODULE_DIR  && mvn clean install -fae -B -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn -Ptestgrid -DskipBenchMarkTest=true -Dhttp.keepAlive=false -Dmaven.wagon.http.pool=false
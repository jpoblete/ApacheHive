#!/bin/bash
#
# Author: j.martinez.poblete@gmail.com
#
# This script will install Hive 4 standalone
# Execute the script from anywhere
# chmod +x ./install.sh
# ./install.sh
#
# Main ENV vars
#
LOG=${0##*/}
LOG=${LOG/sh/log}
export WORK=/opt/apache 
export JAVA_HOME=/usr/java
export PROJECT_HOME=${WORK}/Hive
#
# Foundations
#
function exitState(){
   status=$1
   banner=$2
   if [ "$?" -eq 0 ]; then
      echo "[SUCCESS] ${banner}"
   else
      echo "[FAILURE] ${banner}"
      exit 1
   fi
}
function yumSilent(){
   yum -y -q install "$@"
   exitState "$?" "Installing $@"
}
function createUser(){
   user="$@"
   if [ -z "$(id ${user})" ]; then
      useradd  -b /home ${user}
      groupadd supergroup 
      usermod -a -G supergroup ${user} 
      echo "${user}:${user}" | chpasswd
      su -s /bin/bash -c "echo \"[SUCCESS] Creating user: ${user}\"" - hive
   fi
} 
function getOsTools(){
   cd ${WORK}
   yumSilent java java-devel lsof screen cronie nc 
   jdk=$(alternatives --display java | awk '/link/{print $NF}')
   ln -s ${jdk%/jre*} ${JAVA_HOME}
   git=$(which git) >& /dev/null
   if [ -z "${git}" ]; then
      echo "Installing GIT..."
      yumSilent https://packages.endpointdev.com/rhel/7/os/x86_64/endpoint-repo.x86_64.rpm
      yumSilent install git
   fi
   createUser hive
   git clone git@github.com:jpoblete/Hive.git
   exitState "$?" "Cloning project"
   chmod +x ${PROJECT_HOME}/setup.sh
}       
#
# Main
#
main(){
   if [ -d ${WORK} ]; then
      echo "Seems like this script was already executed"
      echo "Remove ${WORK} and try One Click script again"
      exit 0
   else
      mkdir -p ${WORK}
      getOsTools
      ${PROJECT_HOME}/setup.sh
   fi   
}
main | tee -a /tmp/${LOG}
#EOF

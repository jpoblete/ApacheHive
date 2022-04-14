#!/bin/bash
#
# Author: j.martinez.poblete@cloudera.com
#
# This script is NOT executed directly
# It is invoked from install.sh
#
# Main ENV vars
#
export WORK=/opt/apache
export PROJECT_HOME=${WORK}/ApacheHive
. ${PROJECT_HOME}/functions.sh

export WORK=/opt/apache 
export JAVA_HOME=/usr/java
export TEZ_HOME=${WORK}/tez
export HIVE_HOME=${WORK}/hive
export HADOOP_HOME=${WORK}/hadoop
export DERBY_HOME=${WORK}/db-derby
export PROJECT_HOME=${WORK}/ApacheHive
export TEZ_HOME=${WORK}/tez
ENV="${ENV} export WORK=${WORK};"
ENV="${ENV} export TEZ_HOME=${WORK}/tez"
ENV="${ENV} export JAVA_HOME=${JAVA_HOME};"
ENV="${ENV} export HIVE_HOME=${WORK}/hive;"
ENV="${ENV} export DERBY_HOME=${WORK}/db-derby;"
ENV="${ENV} export HADOOP_HOME=${WORK}/hadoop"
#
# Helpers
#
function listFunctions(){
   awk '/^function/ {print $NF}' ${PROJECT_HOME}/functions.sh | sed -e 's/(){//g' 
}
function showFunction(){
   name=$1
   sed -n '/'${name}'/,/^}/p' ${PROJECT_HOME}/functions.sh
}
function findJar(){
   file="$@"
   find ${WORK} -name "${file}" -type f
}
function findJarByClass(){
   class="$@"
   find ${WORK} -name "*.jar" -type f -exec egrep "${class}" {} \;
}   
function linkHiveLibJar(){
   file="$@"
   ln -s "${file}" ${HIVE_HOME}/lib/${file##*/}
}
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
function waitForSocket(){
   port=$1
   echo "Waiting for process to listen on TCP(${port}) "
   while [ -z "$(lsof -Pni :${port} | egrep LISTEN)" ]; do
         echo -n "."
   done
   echo "!"
   echo "Done"
}
function getPkg(){
   cd ${WORK}
   name=$1
   version=$2
   url=$3
   linkName=$4
   status=1
   file=${url##*/}
   echo "Getting package ${name}-${version} ..."
   wget                           \
      --no-verbose                \
      --no-check-certificate      \
      --output-document="${file}" \
      "${url}"
   status1=$?
   tar xzf  "${file}"
   status2=$?
   ln -s ${file/.tar.gz/} ${linkName}
   status3=$?
   [ ${status1} -eq 0 ] && [ ${status2} -eq 0 ] && [ ${status3} -eq 0 ] && status=0
   exitState ${status} "Getting ${name}-${version}"
}
#
# Main functions
#
function setupMaven(){
   cd ${WORK}
   mvnTGZ="apache-maven-3.6.3-a-bin.tar.gz"
   status=1
   if [ ! -f $PROJECT_HOME/${mvnTGZ} ]; then
      getPkg apache-maven 3.6.3 https://archive.apache.org/dist/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz maven
      status=0
   else
      tar xzf $PROJECT_HOME/${mvnTGZ}
      status1=$?
      ln -s ${mvnTGZ/-bin.tar.gz} maven
      status2=$?
   fi
   mvn=$(find ${WORK} -name mvn -type f)
   ${mvn} -v
   status3=$?
   [ ${status1} -eq 0 ] && [ ${status2} -eq 0 ] && [ ${status3} -eq 0 ] && status=0
   exitState ${status} "Installing apache-maven-3.6.3-a"
   MVN=${mvn}
   export MVN
}
function getHive(){
   #
   # Retrieving the latest Apache Hive build
   #
   cd ${WORK}
   status=1
   version=$(curl "https://archive.apache.org/dist/hive/" |& awk -F\" '/hive-4/{gsub("/</a>.*$","");print $NF}')
   status1=$?
   version=${version/>hive-/}
   getPkg apache-hive ${version} https://archive.apache.org/dist/hive/hive-${version}/apache-hive-${version}-bin.tar.gz ${HIVE_HOME##*/}
   #
   # Retrieving Apache Hive Master 
   # Building from source may be done using hiveCtl
   # NOTE: The latest binary build just downloaded 
   #       MAY BE BEHIND THE NEWEST CODE 
   #
   git clone https://github.com/apache/hive.git apache-hive
   status2=$?
   version=$(egrep -A1 '<artifactId>hive</artifactId>' ${WORK}/apache-hive/pom.xml | tail -1)
   version="${version#*>}"
   version="${version%<*}"
   mv apache-hive apache-hive-${version}
   #cd  hive
   #git fetch origin
   #git rebase
   #${MVN} clean install -DskipTests -Drat.skip=true
   status2=0
   status3=0
   [ ${status1} -eq 0 ] && [ ${status2} -eq 0 ] && [ ${status3} -eq 0 ] && status=0
   exitState ${status} "Cloning apache-hive-${version}"
   HIVE_VERSION=${version}
   export HIVE_VERSION
}
function getHadoop(){
   # Get Hadoop version from Hive pom.xml (currently v3.1.0)
   version=$(awk '/<hadoop.version>[0-9]/' ${WORK}/apache-hive-${HIVE_VERSION}/pom.xml)
   version=${version#*>}
   version=${version%<*}
   getPkg hadoop ${version} https://archive.apache.org/dist/hadoop/common/hadoop-${version}/hadoop-${version}.tar.gz ${HADOOP_HOME##*/}

}
function getDerby(){
   # Get Derby version from Hive pom.xml (currently v10.14.1.0)
   version=$(awk '/<derby.version>[0-9]/' ${WORK}/apache-hive-${HIVE_VERSION}/pom.xml)
   version=${version#*>}
   version=${version%<*}
   getPkg db-derby ${version} https://archive.apache.org/dist/db/derby/db-derby-${version}/db-derby-${version}-bin.tar.gz ${DERBY_HOME##*/}
}
function getTez(){
   # Get Derby version from Hive pom.xml (currently v10.14.1.0)
   version=$(awk '/<tez.version>[0-9]/' ${WORK}/apache-hive-${HIVE_VERSION}/pom.xml)
   version=${version#*>}
   version=${version%<*}
   getPkg apache-tez ${version} https://archive.apache.org/dist/tez/${version}/apache-tez-${version}-bin.tar.gz ${TEZ_HOME##*/}
}
function setStage(){
   cd ${WORK}
   [ -d /root/build/ ] && mv /root/build ${WORK}
   # Project
   chmod +x ${PROJECT_HOME}/hiveCtl
   # Hadoop
   cp $PROJECT_HOME/core-site.xml ${HADOOP_HOME}/etc/hadoop/
   ln -s ${HADOOP_HOME}/etc/hadoop /etc/hadoop
   # Hive
   cp $PROJECT_HOME/hive-* ${HIVE_HOME}/conf/
   mkdir -p /etc/hive /var/log/hive /user/hive /tmp/hive /tmp/warehouse
   ln -s ${HIVE_HOME}/conf /etc/hive/conf 
   chown hive:supergroup /var/log/hive /user/hive /tmp/hive /tmp/warehouse
   chmod 777 /user/hive /tmp/hive /tmp/warehouse
   ln -s /tmp/warehouse /user/hive/warehouse
   # Derby
   mkdir -p /var/log/derby
   chown hive:supergroup /var/log/derby
   # Tez
   mkdir -p /etc/tez
   cp $PROJECT_HOME/tez-site.xml ${TEZ_HOME}/conf
   ln -s ${TEZ_HOME}/conf /etc/tez/conf
   for jar_file in $(ls ${TEZ_HOME}/*.jar); do
       linkHiveLibJar ${jar_file}
   done
   chown hive:supergroup -R ${WORK}/*
}
function startDerby(){
   log=/var/log/derby/derby.log
   su -s /bin/bash -c "${ENV}; cd ${log%/*}; ${DERBY_HOME}/bin/startNetworkServer >& ${log} &" - hive
   waitForSocket 1527
   exitState $? "Start Derby Server"
}
function initSchema(){
   su -s /bin/bash -c "${ENV}; ${HIVE_HOME}/bin/schematool -dbType derby -initSchema --verbose >& /tmp/hive_schema.out" - hive
   su -s /bin/bash -c "${ENV}; ${HIVE_HOME}/bin/schematool -dbType derby -validate   --verbose" - hive
}
function startHMS(){
   cd ${WORK}
   ENV="${ENV}; export PATH=${HIVE_HOME}/bin:${PATH}; export HIVE_LOG=hivemetastore.log"
   su -s /bin/bash -c "${ENV}; hive --service metastore   1>/var/log/hive/hivemetastore.stdout 2>/var/log/hive/hivemetastore.stderr &" - hive
   waitForSocket 9083
   exitState $? "Start Hive Metastore Server"
}
function startHS2(){
   cd ${WORK}
   ENV="${ENV}; export PATH=${HIVE_HOME}/bin:${PATH}; export HIVE_LOG=hiveserver2.log"
   #su -s /bin/bash -c "${ENV}; ${DERBY_HOME}/bin/stopNetworkServer" - hive
   su -s /bin/bash -c "${ENV}; hive --service hiveserver2 1>/var/log/hive/hiveserver2.stdout   2>/var/log/hive/hiveserver2.stderr &"  - hive
   waitForSocket 10000
   exitState $? "Start HiveServer2"
}
function testBL(){
   cd ${WORK}
   jdbc='jdbc:hive2://localhost:10000/default'
   exec='"SHOW DATABASES;"'
   opts="-n hive -p hive --silent=true --showHeader=false --verbose=true"
   test=1
   while [ "${test}" -gt 0 ]; do
         nc -vz localhost 10000
         test=$?
         sleep 5
   done
   su -s /bin/bash -c "${ENV}; ${HIVE_HOME}/bin/hive -u ${jdbc} ${opts} -e ${exec} > /tmp/blTest.out 2>/tmp/blTest.stderr" - hive
   status=$(awk '/default/{print "0"}' /tmp/blTest.out)
   exitState ${status} "Beeline test"
}
function setupRootUsr(){
   echo "Adding variables to root shell environment..."
   cat  ${PROJECT_HOME}/root_profile >> /root/.bash_profile
}
function setupHiveUsr(){
   echo "Setting Hive user shell environment..."
   cat  ${PROJECT_HOME}/bash_profile >> /home/hive/.bash_profile
}
#
# Main
#
main() {
   cd ${HOME}
   setupRootUsr
   setupHiveUsr
   setupMaven
   getHive
   getHadoop
   getDerby
   getTez
   setStage
   startDerby
   initSchema
   validateSchema
   startHMS
   startHS2
   testBL
   exitState 0 "All tasks completed"
}

main
#EOF

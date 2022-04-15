#!bin/bash
#
# Author: j.martinez.poblete@cloudera.com
#
# This script provides functions across scripts
#
LOG=${0##*/}
LOG=${LOG/sh/log}
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
# Script will fail if there are issues with JAVA_HOME
# issues
#
if [ ! -x ${JAVA_HOME}/bin/java ]; then
   JAVA_HOME=$(dirname $(dirname $(find / -name javac -type f | head -1)))
   if [ ! -d  "${JAVA_HOME}" ]; then
      echo "ERROR: Could not find a suitable JAVA_HOME, scripts will fail"
   else
      export  JAVA_HOME
   fi   
fi
#
# Helpers
#
function gitReset(){
   cd ${PROJECT_HOME}
   git fetch origin
   git reset --hard
   git rebase
   chmod +x install.sh setup.sh hiveCtl
   source ~/.bash_profile
}   
function listFunctions(){
   awk '/^function/ {print $NF}' ${PROJECT_HOME}/functions.sh | sed -e 's/(){//g' 
}
function showFunction(){
   name=$1
   sed -n '/^function '${name}'/,/^}/p' ${PROJECT_HOME}/functions.sh
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
   [[ ! -L ${HIVE_HOME}/lib/${file##*/} ]] && ln -s "${file}" ${HIVE_HOME}/lib/${file##*/}
}
function yumSilent(){
   yum -y -q install "$@"
   exitState "$?" "Installing ${@:-2}"
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
   timer=0
   timeout=60
   echo "Waiting for process to listen on TCP(${port}) "
   while [ -z "$(lsof -Pni :${port} | egrep LISTEN)" ]; do
         echo -n "."
         sleep 1
         ((timer++))
         if [ "${timer}" -gt ${timeout} ]; then
            echo "X"
            exitState 1 "Process did not initialize within timeout"
            break
         fi   
   done
   echo "!"
   echo "Done"
   return 0
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
function osExtras(){
   node=$(hostname -f)
   node=${node%%.*}
   node=${node#*-}
   yumSilent file
   #
   # Packages for node1
   #
   yumSilent wget
   if [ "${node}" == "node1" ]; then
      yumSilent https://dev.mysql.com/get/mysql80-community-release-el7-5.noarch.rpm
      yumSilent mysql-server
      /usr/bin/cp -f $PROJECT_HOME/my.cnf /etc/my.cnf
      systemctl start mysqld
      mysql < $PROJECT_HOME/setup.sql
   fi   
}
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
function checkOut(){
   cd ${WORK}
   [ -z "${MVN}" ] && MVN=$(find ${WORK} -name mvn -type f) && export MVN 
   commitId=$1
   status=1
   if [[ -L ${WORK}/hive ]]; then
      version=$(readlink ${WORK}/hive)
      if [ -d ${WORK}/${version/-bin/} ]; then
         echo "Checking out ${commitId} and rebuilding apache-hive"
         echo "NOTE: It will take some time to complete"
         stopHive
         cd ${version/-bin/}
         git checkout ${commitId}
         status1=$?
         ${MVN} -q clean install -DskipTests -Drat.skip=true
         status2=$?
         ${MVN} -q package -Pdist -DskipTests -Dmaven.javadoc.skip=true -Drat.skip=true
         status3=$?
         cd ${WORK}
         unlink ${version} 
         unlink hive
         build=$(ls -1 ${version/-bin/}/packaging/target/*-bin/)
         ln -s ${version/-bin/}/packaging/target/${build}/${build} ${build}
         ln -s ${build} hive
         [ ! -f ${WORK}/hive/conf/hive-site.xml ] && /usr/bin/cp -f ${PROJECT_HOME}/hive-* ${WORK}/hive/conf/
         linkTezLibs
         chown hive:supergroup -R *
         [ ${status1} -eq 0 ] && [ ${status2} -eq 0 ] && [ ${status3} -eq 0 ] && status=0
         exitState ${status} "Checking out ${commitId} & rebuild apache-hive-${version}"
         startHive
      else
         exitState 1 "There is no source code directory for ${version}"
      fi
   else
      exitState 1 "There is no target for ${WORK}/hive"
   fi
}
function getHive(){
   # Retrieving the latest Apache Hive build
   cd ${WORK}
   [ -z "${MVN}" ] && MVN=$(find ${WORK} -name mvn -type f) && export MVN 
   status=1
   #version=$(curl "https://archive.apache.org/dist/hive/" |& awk -F\" '/hive-4/{gsub("/</a>.*$","");print $NF}')
   #status1=$?
   #version=${version/>hive-/}
   #getPkg apache-hive ${version} https://archive.apache.org/dist/hive/hive-${version}/apache-hive-${version}-bin.tar.gz ${HIVE_HOME##*/}
   #
   # Get Master Branch
   #
   git clone https://github.com/apache/hive.git apache-hive
   status1=$?
   version=$(egrep -A1 '<artifactId>hive</artifactId>' ${WORK}/apache-hive/pom.xml | tail -1)
   version="${version#*>}"
   version="${version%<*}"
   echo "Installing Apache Hive ${version}"
   mv apache-hive apache-hive-${version}
   cd apache-hive-${version}
   ${MVN} -q clean install  -DskipTests -Dmaven.javadoc.skip=true -Drat.skip=true
   status2=0
   ${MVN} -q package -Pdist -DskipTests -Dmaven.javadoc.skip=true -Drat.skip=true
   status3=0
   cd ${WORK}
   build=$(ls -1 apache-hive-${version}/packaging/target/*-bin/)
   ln -s apache-hive-${version}/packaging/target/${build}/${build} ${build}
   ln -s ${build} hive
   [ ${status1} -eq 0 ] && [ ${status2} -eq 0 ] && [ ${status3} -eq 0 ] && status=0
   exitState ${status} "Cloning apache-hive-${version}"
   HIVE_VERSION=${version}
   export HIVE_VERSION
}
function rebaseHive(){
   cd ${WORK}
   [ -z "${MVN}" ] && mvn=$(find ${WORK} -name mvn -type f) && MVN=${mvn} && export MVN
   url="https://raw.githubusercontent.com/apache/hive/master/pom.xml"
   status=1 
   wget                        \
   --no-verbose                \
   --no-check-certificate      \
   --output-document="pom.xml" \
   "${url}"
   status1=$?
   version=$(egrep -A1 '<artifactId>hive</artifactId>' ${WORK}/pom.xml | tail -1)
   version="${version#*>}"
   version="${version%<*}"
   echo ${version}
   if [ ! -d apache-hive-${version} ]; then
      git clone https://github.com/apache/hive.git apache-hive-${version}
      status2=$?
   else
      status2=0
   fi
   rm -f ${WORK}/pom.xml
   unlink $(readlink hive)
   unlink hive
   cd apache-hive-${version}
   git fetch origin
   git rebase
   echo "Compiling apache-hive-${version}"
   echo "NOTE: It will take time to complete"
   ${MVN} -q clean install -DskipTests -Drat.skip=true
   status3=$?
   ${mvn} -q package -Pdist -DskipTests -Dmaven.javadoc.skip=true -Drat.skip=true
   status4=$?
   cd ${WORK}
   build=$(ls -1 apache-hive-${version}/packaging/target/*-bin/)
   ln -s apache-hive-${version}/packaging/target/${build}/${build} ${build}
   ln -s ${build} hive
   [ ! -f ${WORK}/hive/conf/hive-site.xml ] && /usr/bin/cp -f ${PROJECT_HOME}/hive-* ${WORK}/hive/conf/
   linkTezLibs
   chown hive:supergroup -R apache-hive-${version}-bin/
   [ ${status1} -eq 0 ] && [ ${status2} -eq 0 ] && [ ${status3} -eq 0 ] && [ ${status4} -eq 0 ] && status=0
   exitState ${status} "Building apache-hive-${version}"
}
function switchHiveBuild(){
   cd ${WORK}
   echo "Available builds:"
   ls -1 ${WORK} | egrep "apache-hive-.*-bin$"
   echo "Enter new HIVE_HOME directory: "
   read newHive
   if [ -d "${newHive}" ]; then
      stopHive
      [[ -L ${WORK}/hive ]] && unlink ${WORK}/hive
      ln -s ${newHive} hive
      /usr/bin/cp -f $PROJECT_HOME/hive-* ${HIVE_HOME}/conf/
      chown hive:supergroup ${HIVE_HOME}/conf/*
      linkTezLibs
      startHive
      exitState 0 "New HIVE_HOME=${newHive} - Remember to validate/upgradeSchema"
   else
      exitState 1 "Build directory does not exist"
   fi
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
function linkTezLibs(){
   for jar_file in $(ls ${TEZ_HOME}/*.jar); do
       linkHiveLibJar ${jar_file}
   done
}
function setStage(){
   cd ${WORK}
   [ -d /root/build/ ] && mv /root/build ${WORK}
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
   linkTezLibs
   chown hive:supergroup -R ${WORK}/*
}
function startDerby(){
   log=/var/log/derby/derby.log
   su -s /bin/bash -c "${ENV}; cd ${log%/*}; ${DERBY_HOME}/bin/startNetworkServer >& ${log} &" - hive
   waitForSocket 1527
   exitState $? "Start Derby Server"
}
function stopDerby(){
   log=/var/log/derby/derby.log
   su -s /bin/bash -c "${ENV}; cd ${log%/*}; ${DERBY_HOME}/bin/stopNetworkServer >& ${log} &" - hive
   exitState $? "Start Derby Server"
}
function schemaTool(){
   # Options should really be set on hive-site.xml
   cmd=$1
   dbType=$2
   [ -z "${dbType}" ] && dbType=derby
   # Fix MySQL 
   # Error: Specified key was too long; max key length is 767 bytes (state=42000,code=1071)
   [ "${dbType}" == "mysql" ] && sed -i 's/(256)/(255)/g' /opt/apache/hive/scripts/metastore/upgrade/mysql/hive-schema-4.0.0-alpha-1.mysql.sql
   url=$3
   [ "${url}" ] && cmd="-url ${url} ${cmd}"
   su -s /bin/bash -c "${ENV}; ${HIVE_HOME}/bin/schematool -dbType ${dbType} ${cmd} --verbose; echo $? > /tmp/status.out" - hive
   exitState $(cat /tmp/status.out) "Executing schemaTool ${cmd}" && rm -f /tmp/status.out
}
function initSchema(){
   schemaTool -initSchema 
}
function validateSchema(){
   schemaTool -validate
}
function reInitSchema(){
   stopDerby
   mv /home/hive/metastore_db /home/hive/metastore_db_$(date '+%s')
   startDerby
   initSchema
   validateSchema
}
function statusHive(){
   pids=$(ps -ef | awk '!/awk/ && (/HiveMetaStore/ || /HiveServer2/) {print $2}')
   if [ "${pids}" ]; then
      for pid in ${pids}; do
          lsof -Pnp ${pid} | awk '/LISTEN/ {print "pid="$2,"owner="$3,"bind="$(NF-1)}'
      done
      exitState 0 "Hive processes are running"
   else
      exitState 0 "Hive processes are stopped"   
   fi
   return 0
}
function startHive(){
   startHMS
   startHS2
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
   su -s /bin/bash -c "${ENV}; hive --service hiveserver2 1>/var/log/hive/hiveserver2.stdout   2>/var/log/hive/hiveserver2.stderr &"  - hive
   waitForSocket 10000
   exitState $? "Start HiveServer2"
}
function stopProcess(){
   server=$1
   pids=$(ps -ef | awk '!/awk/ && ( /'"${server}"'/ ){print $2}')
   if [ -z "${pids}" ]; then
      exitState 0 "${server} process is already stopped"
   else   
      for pid in ${pids}; do
          kill -SIGTERM "${pid}"
          echo "SIGTERM on ${pid}: $?" 
      done
      sleep 5
      #stopProcess ${server}
      #while [ "${pids}" ]; do
      #      pids=$(ps -ef | awk '!/awk/ && ( /'"server"'/ ){print $2}')
      #      echo -n "."
      #      sleep 1
      #done
      #echo "!"
      exitState 0 "${server} process stopped"
   fi   
}
function stopHMS(){
   stopProcess HiveMetaStore 
}
function stopHS2(){
   stopProcess HiveServer2
}
function stopHive(){
   stopHMS
   stopHS2
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

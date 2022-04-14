#
# Author: j.martinez.poblete@cloudera.com
# 
# This is for hive environment to be set
#
export WORK=/opt/apache
export JAVA_HOME=/usr/java
export TEZ_HOME=${WORK}/tez
export HIVE_HOME=${WORK}/hive
export HADOOP_HOME=${WORK}/hadoop
export DERBY_HOME=${WORK}/db-derby
export PATH="${HIVE_HOME}/bin:${PATH}"
export PROJECT_HOME=${WORK}/ApacheHive
. ${PROJECT_HOME}/functions.sh 
alias  beeline="${HIVE_HOME}/bin/beeline -u jdbc:hive2://localhost:10000/default -n hive -p hive --verbose=true"

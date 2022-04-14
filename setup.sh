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
#
# Main
#
main() {
   cd ${HOME}
   osExtras
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

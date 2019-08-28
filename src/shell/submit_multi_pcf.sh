#!/bin/bash

##
#Assumptions: assumes the following structure under the parent directory
#  of this script
#   1) cfgs
#   2) src
## Assumptions: assumes the following config files in the cfgs directory
#  1) jenkins.cfg
# 
#Usage:
# ./submit_job.sh path2/pipeline.cfg server_type [sampleID]
# 
#What it does:
#  The program triggers a pipeline build on Jenkins for each sample listed 
#  in the design file(Example 1) orfor the specified sampleID 
#
source /etc/profile.d/biocore.sh

cd `dirname $0`
script_name=`basename $0`
## Check expected structure
working_dir=`pwd`
parent_dir=`dirname $working_dir`
cfg_dir_base=`dirname $parent_dir`
cfgs_dir=$cfg_dir_base/cfgs

PIPELINE_CONFIG_FILE=$1
SERVER_TYPE=$2
sample_id=$3
JENKINS_CONFIG=$cfgs_dir/jenkins.cfg
CWLTOOL=`which cwltool`
CURRENT_USER=`id -un`
#CURRENT_USER=bioadmin

if [ ! -d $cfgs_dir ]
then
   echo "ERROR: Expected cfgs directory missing under $parent_dir"
   exit 1
fi

if [ ! -f $JENKINS_CONFIG ]
then
   echo "ERROR: Missing jenkins.cfg under $cfgs_dir"
   exit 1
fi
if [ ! -f ${CWLTOOL} ]
then
  echo "ERROR: cwltool not installed on `uname -n ` - see ${CWLTOOL}" 
  exit 1
fi
if [ -z "${PIPELINE_CONFIG_FILE}" ]
then
   echo "********************************************************"
   echo""
   echo "Usage: ./$script_name path2runID/cfgs/pipeline.cfg [server_type] [sampleID]"
   echo""
   echo "Where:"
   echo "pipeline.cfg: Required - is the full path to your pipeline project config file."
   echo "              The pipeline config file is generated by running the program gen_config.sh"
   echo "server_type:  Required - Platform [cloud | local] to launch the pipelines - by default local servers are used."
   echo "sampleID:     Optional - is the sample Id as found in the experiment design file."
   echo "              Default, triggers a pipeline run for each sample listed in the design file."
   echo ""
   echo ""
   echo "Example 1: ./$script_name path2runID/cfgs/pipeline.cfg"
   echo ""
   echo "The program triggers a pipeline build on Jenkins for each sample listed in the design file(Example 1) or"
   echo "for the specified sampleID "
   echo ""
   exit 1
fi
source ${PIPELINE_CONFIG_FILE}
source ${JENKINS_CONFIG}
## 
log=$LOG_BASE/$script_name.log
[ -f $log ] && rm -f $log
touch $log

 echo ""|tee -a $log
 echo "************************************************************************" | tee -a $log
 echo "*      Launching $PROJECT_NAME pipelines on Jenkins                   "| tee -a $log
 echo "*                                                  "| tee -a $log
 echo "*      Project Team: $PROJECT_TEAM_NAME            "| tee -a $log
 echo "*      Project Name: $PROJECT_NAME                 "| tee -a $log
 echo "*      Organism:       $ORGANISM                   "| tee -a $log
 echo "*      Design File:  $DESIGN_FILE                  "| tee -a $log
 echo "*      Date:  `date`                  "| tee -a $log
 echo "*      Current User: `id -un`                  "| tee -a $log
 echo "*      Pipeline Owner: ${PIPELINE_OWNER}                 "| tee -a $log
 echo "*      Results Base:  $RESULTS_DIR                "| tee -a $log
 echo "*      Sample PCF Files Base:$PIPELINE_META_BASE                  "| tee -a $log
 echo "*      Sample Json Files Base:$PATH2_JSON_FILES                  "| tee -a $log
 echo "************************************************************************" | tee -a $log
 echo ""| tee -a $log

JENKINS_JOB=${DEFAULT_JENKINS_JOB[$SERVER_TYPE]}
[ -z "$JENKINS_JOB" ] && JENKINS_JOB=${DEFAULT_JENKINS_JOB[local]}

launch_build(){
  METADATA_SCRIPT=$PIPELINE_META_BASE/$sample_id.$ORGANISM.pcf
  if [ -f ${METADATA_SCRIPT} ]
  then
     echo "**************************************" | tee -a $log
     echo "SampleID: $sample_id" | tee -a $log
     echo "Sample pcf file: ${METADATA_SCRIPT}" | tee -a $log
     echo "CMD: ssh -l $CURRENT_USER -p  $JENKINS_SSH_PORT  $JENKINS_URL build $JENKINS_JOB \
     -p PIPELINE_METADATA_SCRIPT=$METADATA_SCRIPT" | tee -a $log
     ssh -l $CURRENT_USER -p  $JENKINS_SSH_PORT $JENKINS_URL  build $JENKINS_JOB -p PIPELINE_METADATA_SCRIPT=$METADATA_SCRIPT
  else
     echo "SKIPPING: SampleID - $sample_id"  | tee -a $log 
     echo "ERROR: The pcf file ${METADATA_SCRIPT} - not found  on `uname -n ` "   | tee -a $log
  fi
}
if [ -z "$sample_id" ]
then
  for sample_id in ${SAMPLES}
  do
     launch_build $sample_id
  done
else
    launch_build $sample_id
fi
date
exit 0


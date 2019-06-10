#!/bin/bash

##
## Rsynces software required to run a pipeline projects on the cloud
#  Software is migrated between local and remote servers
# 
#Usage:
# ./rsync_project.sh path2/pipeline.cfg RSEM-v1.3.0,STAR-2.6.1b
#
## Assumptions: assumes the following structure under the working directory
#   1) cfgs
#   2) src
## Assumptions: assumes the following config files in the cfgs directory
#  1) biocore.cfg
# 
#Notes:
# The script flags instances where the expected file/dir to transfer is missing.
# At completion, the log checker then scan the generated log file for errors 
# - reports and sets the migration status accordingly 
#
source /etc/profile.d/biocore.sh

cd `dirname $0`
script_name=`basename $0`
## Check expected structure
working_dir=`pwd`
parent_dir=`dirname $working_dir`
cfgs_dir=$parent_dir/cfgs

PIPELINE_CONFIG_FILE=$1
INDEXERS=$2

CURRENT_USER=`id -un`
rsync_options=' -avz  --exclude=.snapshot --exclude=results --exclude=logs'
#
#Tokens used to check the migration status
ERROR_TERMS="ERROR error failed"

rsync_prog=`which rsync`
if [ ! -f $rsync_prog ]
then
   echo $rsync_prog
   echo "'rsync' not installed on `uname -n`"
   exit 1
fi
if [ ! -d $cfgs_dir ]
then
   echo "ERROR: Expected cfgs directory missing under $parent_dir"
   exit 1
fi
if [ ! -f $cfgs_dir/biocore.cfg ]
then
   echo "ERROR: Missing biocore.cfg under $cfgs_dir"
   exit 1
fi
source  $cfgs_dir/biocore.cfg

rsync_script="$rsync_prog $rsync_options"


prog_usage(){
   echo "********************************************************"
   echo""
   echo "Usage: ./$script_name path2/pipeline.cfg [indexers]"
   echo""
   echo "Where:"
   echo "path2_pipeline.cfg: Required - is the full path to your pipeline project config file."
   echo " The pipeline config file is generated by running the program gen_config.sh"
   echo "indexers: Optional - commas separated list of indexers used as found under /data/transformed "
   echo ""
   echo "Example : ./$script_name /data/scratch/rna-seq/VootYin/Mouse_KO_2019/results/cfgs/pipeline.cfg RSEM-v1.3.0,STAR-2.6.1b"
   echo ""
   echo "The program triggers a data transfer between the local file system and our S3 buckets."
   echo " Only data associated to a project is transfered. "
   echo ""
   echo "Data to transfer to the cloud:"
   echo "1) /data/scratch/rna-seq/team-name/project_dir"
   echo "2) /path2pcf_files/pipeline-runs-meta/project_dir"
   echo "3) /path2json_files/rna-seq/project_dir"
   echo "4) /path2/cwl_script"
   echo "5) /data/transformed/indexer/dataset-version/organism*"
   echo "6) /data/scratch/dataset-version/organism*"
   echo ""
}
if [ -z "${PIPELINE_CONFIG_FILE}" ]
then
   echo" Must specify the path2/pipeline.cfg"
   prog_usage
   exit 1
fi
source ${PIPELINE_CONFIG_FILE}

log=$script_name.log
rm -f $log
touch $log

## Checks logs for failure 
function getLogStatus() {
  log=$1
  IFS=""
  rstatus="Success"
  for ((i = 0; i < ${#ERROR_TERMS[@]}; i++))
  do
       error_term=${ERROR_TERMS[$i]}
       error_found=`grep -i $error_term $log `
       if [ "$error_found" != "" ]
       then
            rstatus="Failure"
            echo "Found: \"$error_found\" "   
        fi
  done
  echo "$rstatus" 
}
echo "********************************************************" | tee -a $log
echo "Rsyncing data for project:$PROJECT_NAME  " | tee -a $log
echo "********************************************************"| tee -a $log  

date
## We migrate the entire software directory to cloud 
#  Since both json files and pcf files are expected to be installed under
# 
PROJECT_META_BASE=$PIPELINE_META_BASE/$PROJECT_NAME
PROJECT_JSON_BASE=$PATH2_JSON_FILE

#CWL_SCRIPT
cd $working_dir
## Check that the cwl script exist
if [ ! -f $CWL_SCRIPT ]
then
  echo "ERROR: The main cwl file ${CWL_SCRIPT} - not found  on `uname -n ` " | tee -a $log
fi
## Check that a pcf file was generated for each sample
## and for each pcf, check that the specified json file 
#  and the cwl script exist 

issue_found=false
for sample_id in ${SAMPLES}
do
   #The pcf file name format: sample_id.organism.pcf
   if [ -f  $PROJECT_META_BASE/$sample_id.$ORGANISM.pcf ]
   then
        source $PROJECT_META_BASE/$sample_id.$ORGANISM.pcf
        if [ ! -f $CWL_SCRIPT ]
        then 
            issue_found=true
            echo "ERROR: Invalid cwl file ${CWL_SCRIPT} in $PROJECT_META_BASE/$sample_id.$ORGANISM.pcf " | tee -a $log
        fi
        if [ ! -f $JSON_FILE ]
        then
            issue_found=true  
            echo "ERROR: Invalid json file ${JSON_FILE} in $PROJECT_META_BASE/$sample_id.$ORGANISM.pcf " | tee -a $log
        fi
   else
     echo "ERROR: The pcf file $PROJECT_META_BASE/$sample_id.$ORGANISM.pcf - not found  on `uname -n ` " | tee -a $log
     issue_found=true
   fi 
done

#Path to the reference data
database_version=$REF_DATABASE-$REF_DATABASE_VERSION
dataset_base=$BIOCORE_SCRATCH_BASE/$database_version
aws_dataset_base=$AWS_SCRATCH_BASE/$database_version
#Path to the reads and design file
reads_base=$SCRATCH_BASE/$PROJECT_TEAM_NAME/$PROJECT_NAME
aws_reads_base=$AWS_SCRATCH_READS_BASE/$PROJECT_TEAM_NAME/$PROJECT_NAME
cwl_base=`dirname $CWL_SCRIPT`
echo "***************************************************************"| tee -a $log
echo "Data Migration Started:"`date`| tee -a $log
echo "Local Server:"`uname -n`| tee -a $log
echo "Migrating data for project:$PROJECT_NAME"| tee -a $log
echo "***************************************************************"|tee -a $log
echo "" | tee -a $log
echo "" | tee -a $log
## rsync json files
if [ -d $PATH2_JSON_FILES ]
then
    echo `date`" - Migrating json files: $PATH2_JSON_FILES to $AWS_PIPELINE_PROJECTS_BASE"| tee -a $log 
    [ ! -d $AWS_PIPELINE_PROJECTS_BASE/$PROJECT_NAME ] && mkdir -p $AWS_PIPELINE_PROJECTS_BASE/$PROJECT_NAME
    ${rsync_script} $PATH2_JSON_FILES/ $AWS_PIPELINE_PROJECTS_BASE/$PROJECT_NAME 2>&1 | tee -a $log
else
    echo `date`" - ERROR: json files base directory $PATH2_JSON_FILES missing "| tee -a $log 
fi
echo "" | tee -a $log
# rsync pcf files
if [ -d $PIPELINE_META_BASE/$PROJECT_NAME ]
then
    echo `date`" - Migrating pcf files: $PIPELINE_META_BASE/$PROJECT_NAME to $AWS_PIPELINE_META_BASE"| tee -a $log
    [ ! -d $AWS_PIPELINE_META_BASE/$PROJECT_NAME ] && mkdir -p $AWS_PIPELINE_META_BASE/$PROJECT_NAME
    ${rsync_script} $PIPELINE_META_BASE/$PROJECT_NAME/ $AWS_PIPELINE_META_BASE/$PROJECT_NAME 2>&1 | tee -a $log
else
    echo `date`" - ERROR: pcf files base directory $PIPELINE_META_BASE/$PROJECT_NAME missing "| tee -a $log           
fi
#
# rsync sequence reads
echo "" | tee -a $log
echo `date`" - Migrating sequence reads: $reads_base to $AWS_SCRATCH_READS_BASE/$PROJECT_TEAM_NAME"| tee -a $log
[ ! -d $aws_reads_base ] && mkdir -p $aws_reads_base
${rsync_script}  $reads_base $AWS_SCRATCH_READS_BASE/$PROJECT_TEAM_NAME/ 2>&1 | tee -a $log

echo "" | tee -a $log
# rsync reference datasets
echo `date`" - Migrating reference dataset:$dataset_base/$ORGANISM* to $aws_dataset_base/"| tee -a $log
[ ! -d $aws_dataset_base ] && mkdir -p $aws_dataset_base
${rsync_script} $dataset_base/$ORGANISM* $dataset_base/ 2>&1 | tee -a $log

echo "" | tee -a $log
# rsync reference indexes (data/transform) for each index tool used in the pipeline
issue_found=false
if [ ! -z $INDEXERS ]
then
  IFS=',' read  -a indexers_list <<< "$INDEXERS"
  for indexer in "${indexers_list[@]}"
  do
    local_index_base=$INDEX_BASE/$indexer/$database_version
    if [ ! -d $local_index_base ]
    then
       issue_found=true
       echo `date`" - ERROR $database_version reference indexes for $indexer not found" | tee -a $log
    else
        aws_index_base=$AWS_INDEX_BASE/$indexer/$database_version
        echo `date`" - Migrating $indexer reference indexes: $local_index_base/$ORGANISM* to $aws_index_base/"| tee -a $log
        [ ! -d $aws_index_base ] && mkdir -p $aws_index_base
        ${rsync_script} $local_index_base/$ORGANISM* $aws_index_base/ 2>&1 | tee -a $log
    fi
    echo "" | tee -a $log
  done
fi
echo "" | tee -a $log
#rsync software directory,
echo `date`" - Migrating software: $BIOCORE_SOFTWARE_BASE/ to $AWS_SOFTWARE_BASE/"| tee -a $log
${rsync_script} $BIOCORE_SOFTWARE_BASE/ $AWS_SOFTWARE_BASE 2>&1 | tee -a $log
#
echo " " | tee -a ${log}
echo "******************************************************" | tee -a ${log}
echo "Data migration sanity check" | tee -a ${log}
migration_status=`getLogStatus ${log}`
echo "${migration_status}" | tee -a $log
[ "${migration_status}" != Success ] && exit 1
#
echo ""
echo "Data Migration Complete Successfully:"`date`| tee -a $log
date
exit 0

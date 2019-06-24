# -*- coding: utf-8 -*-
from os.path import join,isfile,isdir,basename
import getopt,os,sys,re
import io,json
import subprocess as sp
from datetime import date

'''
Organization: MDIBL
Author: Lucie N. Hutchins
Contact: lucie.hutchins@mdibl.org
Date: June 2019

'''
def get_header():
    header='''
****************** json_generator ********************************************************

The tool generates sample-specific json files for a given experiment

***************************************************************************************
    '''
    return header

def prog_usage():
    usage=get_header()
    usage+='''

 Usage: PROG [-h] -c path2project_runID_main_config/cfgs/pipeline.cfg [-j path2project_runID_json_template/cfgs/template.json] [-s fastq]
 Where:
     -h To show the usage
     -c path2runID/cfgs/pipeline.cfg or --cfg=path2runID/cfgs/pipeline.cfg  ... required, 
     -j path2runID/cfgs/template.json or --jtemp=path2runID/cfgs/template.json ... optional
                                        (default - gets template path from pipeline.cfg), 
     -s fatsq.gz or --suffix=fastq.gz ... optional(default fastq), reads files suffix 
      
 What It Does: Uses the json template to generate sample-specific json files under 
               the location specified in the pipeline.cfg for json files. 

 Example: 
       python PROG  -c path2results/teamName/projectName/runID/cfgs/pipeline.cfg -s fastq
       OR 
       python PROG  -c path2results/teamName/projectName/runID/cfgs/pipeline.cfg 
                    -j path2results/teamName/projectName/runID/cfgs/template.json
       OR
       python PROG  --cfg=path2results/teamName/projectName/runID/cfgs/pipeline.cfg 
 
 ASSUMPTIONS: 
       1) User has full permission to create sample-specific json files
       2) The json template has been generated in the same directory as the pipeline.cfg file
   '''
    print("%s"%(usage))
##
# A data model to store sample info
#
class SampleDOM:
    def __init__(self,sample_id,reads_list,reads_suffix):
        self.id=sample_id
        self.reads=[]
        self.set_sample(reads_list,reads_suffix)

    def set_sample(self,reads_list,reads_suffix):
        if reads_list:
            for read_file in reads_list:
                if read_file.startswith(self.id) and read_file.endswith(reads_suffix):
                    self.reads.append(read_file)
    
    def get_read_file(self,read_number):
        # Logic:
        # if the len of sample_reads array is one, return the first element
        # else:
        #    use the map-reduced algorithm to get the right file name
        #
        if len(self.reads)<=0: return None
        elif len(self.reads)<2: return self.reads[0]
        else:
            # Map step
            #   Create a list of string tokens using one string(read_file)
            ##  we want our regular expression to capture both "_" and non-alphanumeric characters
            tokens=re.split(r'[\W+|_]',self.reads[0])
            # Create a dictionary with read_file:read_file.tokens  key:value pair
            reads={}
            for read_file in self.reads:reads[read_file]=re.split(r'[\W+|_]',read_file)
            # Reduction step - reduce each dict>value using string tokens
            for token in tokens:
                if token in read_number: continue
                for read_file in reads:
                    if token in reads[read_file]:reads[read_file].remove(token)
            # Assembly and quantification step
            read_file=None
            for read in reads:
                if read_number in reads[read]:read_file=read
            return read_file
## Get global environment variables
## setting  from this project runID main config file 
def loadEnv(config_file):
    project_env={}
    output=sp.Popen("source "+config_file+";env",shell=True, stdout=sp.PIPE, stderr=sp.STDOUT).stdout.read()
    for line in output.splitlines():
        if "=" in line:
            try:
                key,value=line.split("=")
                project_env[key]=value
            except:pass
    return project_env

def mkdir_p(path):
    try:
        os.makedirs(path)
    except OSError as exc:  # Python >2.5
        #if exc.errno == errno.EEXIST and isdir(path):
        pass

if __name__== "__main__":
    try:
        opts, args = getopt.getopt(sys.argv[1:], "hc:j:s:", 
                    ["help", "cfg=","jtemp=","suffix"])
    except getopt.GetoptError as err:
        # print help information and exit:
        print("ERROR:%s" % (str(err) )) # will print something like "option -a not recognized"
        prog_usage()
        sys.exit(1)
    #set program arguments
    json_template=None
    pipeline_config=None
    log_file=None
    json_base_dir=None
    design_file=None
    reads_suffix="fastq"
    for o, a in opts:
        if o in ("-c", "--cfg"):pipeline_config = a
        elif o in ("-j","--jtemp"):json_template = a
        elif o in ("-s","--suffix"):reads_suffix = a
        elif o in ("-h", "--help"):
            prog_usage()
            sys.exit()
        else:
            assert False, "unhandled option"
    if pipeline_config is None or not isfile(pipeline_config):
        msg="ERROR: pipeline.cfg missing"
        print("%s - Check %s"%(msg,pipeline_config))
        prog_usage()
        sys.exit()
    #get project global environment variables 
    # variables of interest for this step:
    #  1)LOG_BASE
    #  2)JSON_TEMPLATE
    #  3)PATH2_JSON_FILES
    #  4)DESIGN_FILE  
    #  5)READS_BASE
    #  6)RUN_ID
  
    project_env=loadEnv(pipeline_config)  
    if not project_env["LOG_BASE"]:
        print("ERROR: Log directory missing - see:%s"%(project_env["LOG_BASE"]))
        print("create the above directory and try again.")
        sys.exit()
    if not project_env["PATH2_JSON_FILES"]:
        print("ERROR: Json files base directory missing - see:%s"%(project_env["PATH2_JSON_FILES"]))
        print("create the above directory and try again.")
        sys.exit()
    if not project_env["READS_BASE"]:
        print("ERROR: Path to Reads files is incorrect - see:%s"%(project_env["READS_BASE"]))
        sys.exit()
    if not isdir(project_env["READS_BASE"]):
        print("ERROR: Path to Reads files not a directory - see:%s"%(project_env["READS_BASE"]))
        sys.exit()

    if not isdir(project_env["LOG_BASE"]):
        mkdir_p(project_env["LOG_BASE"])
    log_file=join(project_env["LOG_BASE"],basename(__file__)+".log")
    if not isdir(project_env["PATH2_JSON_FILES"]):
        mkdir_p(project_env["PATH2_JSON_FILES"])
    json_base_dir=project_env["PATH2_JSON_FILES"]
    if json_template is None: 
        json_template=project_env["JSON_TEMPLATE"]
    design_file=project_env["DESIGN_FILE"]
    project_run_id=""
    if "RUN_ID" in project_env:
        project_run_id=project_env["RUN_ID"]

    if not isdir(json_base_dir):
        print("ERROR: Json files base directory does not exist - see:%s"%(json_base_dir))
        print("create the above directory and try again.")
        sys.exit()
    if not isfile(design_file): 
        print("ERROR: The design file is  missing - see:%s"%(design_file))
        sys.exit()
    if not isfile(json_template):
        print("ERROR: Json template file is  missing - see:%s"%(json_template))
        sys.exit()
    ## get list of reads file names
    reads=[f for f in os.listdir(project_env["READS_BASE"]) if isfile(join(project_env["READS_BASE"],f))] 
    print reads
    json_obj=None
    with open(json_template) as f:
        json_obj=json.load(f)
    if json_obj is None:
        print("ERROR: Failed to open Json template - see:%s"%(json_template))
        sys.exit()
    log=open(log_file,'w') 
    log.write("**********************************\n")
    log.write("**********************************\n")
    log.write("Date:%s\n"%( date.today()))
    log.write("\n")
    log.write("Log file:%s\n"%(log_file))
    log.write("Json template:%s\n"%(json_template)) 
    log.write("Json files base directory:%s\n"%(json_base_dir)) 
    log.write("Experiment Design File:%s\n"%(design_file))
    bad_format=False
    json_obj["project_run_id"]=project_run_id

    with open(design_file,'r') as f:
        try:
            for line in f.readlines():
                if "Sample" in line:continue
                if "sample_id" in line:continue
                #Remove leading and trailing whitespace from line
                line=line.strip()
                fields=line.split('\t')
                sample=SampleDOM(fields[0].strip(),reads,reads_suffix)
                read_file_format='sampleID[delimiter]readID[delimiter][...]suffix'
                log.write("----------------------------\n")
                log.write("SampleID:%s\n"%(sample.id))
                log.write("Number of Reads:%d\n"%(len(sample.reads)))
                if len(sample.reads)<=0:
                    log.write("ERROR: Bad read files name - expected format - %s\n"%(read_file_format))
                    bad_format=True
                    continue
                read1=join(project_env["READS_BASE"],sample.get_read_file("1"))
                read2=None
                sample_json_obj=json_obj
                sample_json_file=join(json_base_dir,sample.id+"."+project_env["ORGANISM"]+".json")
                sample_json_obj["input_fastq_read1_files"][0]["path"]=read1
                if len(sample.reads)>1:read2=join(project_env["READS_BASE"],sample.get_read_file("2"))
                log.write("  READ1:%s\n"%(read1))
                if read2 is not None:
                    log.write("  READ2:%s\n"%(read2))
                    sample_json_obj["input_fastq_read2_files"][0]["path"]=read2
                log.write("Json file:%s\n"%(sample_json_file))
                try:
                    to_unicode = unicode
                except NameError:
                    to_unicode = str
                with io.open(sample_json_file, 'w', encoding='utf8') as outfile:
                     str_ = json.dumps(sample_json_obj,indent=2, sort_keys=True,separators=(',', ': '), ensure_ascii=False)
                     outfile.write(to_unicode(str_))
                print("Sample:%s\nJson file:%s\n"%(sample.id,sample_json_file))
        except:raise
    if bad_format:
        log.write("Failed\n")
        print("Program failed\n")
        sys.exit(1)

    log.write("Program complete\n")
    print("Program complete\n")
    sys.exit()

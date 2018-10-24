import os
from os.path import join
import yaml
import numpy as np
import pandas as pd
from snakemake.utils import validate, min_version

from snakemake.remote import FTP
FTP = FTP.RemoteProvider()

min_version("5.1.2") #minimum snakemake version

# read in sample info 
samples = pd.read_table(config["samples"],dtype=str).set_index(["sample", "unit"], drop=False)

BASE = config.get('basename','tara')
experiment_suffix = config.get('experiment_suffix')

if experiment_suffix:
    OUT_DIR = BASE + "_out_" + experiment_suffix
else:
    OUT_DIR = BASE + '_out'

DATA_DIR = config.get('data_directory', join(OUT_DIR, 'data'))
download_data = config.get('download_data', False)

LOGS_DIR = join(OUT_DIR, 'logs')
TRIM_DIR = join(OUT_DIR,"trimmed")
ASSEMBLY_DIR = join(OUT_DIR,"assembly")

#get ftp download targets
SAMPLES = (samples['sample'] + '_' + samples['unit']).tolist()
data_targs, trim_targs = [], []
extensions = ["_1.fq.gz", "_2.fq.gz"]
trim_ext = ["_1.trim.fq.gz", "_2.trim.fq.gz", "_1.se.trim.fq.gz", "_2.se.trim.fq.gz"]
for s in SAMPLES: 
    data_targs = data_targs +  [s + e for e in extensions]
    trim_targs = trim_targs + [s + e for e in trim_ext]

TARGETS = []

if download_data:
    include: 'rules/ftp.rule'
else:
    include: 'rules/link_data.rule'

#data_targs = [join(DATA_DIR, targ) for targ in data_targs] 
# Assembly Targets
trinity_extensions = ['_trinity.fasta', '_trinity.fasta.gene_trans_map']
trinity_targets = ['{}'.format(BASE) + i for i in trinity_extensions]
trinity_targs = [join(ASSEMBLY_DIR, t) for t in trinity_targets]
spades_targets = [join(ASSEMBLY_DIR, t) for t in [BASE + '_spades.fasta']]

#TARGETS = TARGETS + download_targs + [join(TRIM_DIR, targ) for targ in trim_targs] #+ trinity_targs
#TARGETS =  [join(TRIM_DIR, targ) for targ in trim_targs]
TARGETS = trinity_targs + spades_targets
#TARGETS = [join(TRIM_DIR, targ) for targ in trim_targs]

rule all:
    input: TARGETS

trim_params = config['trimmomatic']

rule trimmomatic_pe:
    """
    Trim reads from the sequencer by trimming or dropping low-quality reads.
    """
    input:
	    r1= lambda wildcards: join(DATA_DIR, '{}_{}_1.fq.gz'.format(wildcards.sample,wildcards.unit)), #unpack(get_pretrim_pe) 
	    r2= lambda wildcards: join(DATA_DIR, '{}_{}_2.fq.gz'.format(wildcards.sample,wildcards.unit))

    output:
        r1=join(TRIM_DIR, "{sample}_{unit}_1.trim.fq.gz"),
        r2=join(TRIM_DIR, "{sample}_{unit}_2.trim.fq.gz"),
        r1_unpaired=join(TRIM_DIR, "{sample}_{unit}_1.se.trim.fq.gz"),
        r2_unpaired=join(TRIM_DIR, "{sample}_{unit}_2.se.trim.fq.gz"),
    message:
        """--- Quality trimming PE read data with Trimmomatic."""
    threads: 4
    params:
        trimmer = (trim_params['trim_cmd'].format(trim_params['adapter_file']['pe_name'])).split(' '),
        extra = '' 
    log: join(LOGS_DIR, 'trimmomatic/{sample}_{unit}_pe.log')
    conda:"trimmomatic-env.yaml"
    script:"trimmomatic-pe.py"

rule trinity:
    input:
            left=expand(join(TRIM_DIR, '{sample}_{end}.trim.fq.gz'), sample=SAMPLES, end=["1", "1.se","2.se"]), 
	    right=expand(join(TRIM_DIR, '{sample}_2.trim.fq.gz'), sample=SAMPLES)
    output:
        fasta = join(ASSEMBLY_DIR,"trinity_out_dir/Trinity.fasta"),
        gene_trans_map = join(ASSEMBLY_DIR,"trinity_out_dir/Trinity.fasta.gene_trans_map"),
    message:
        """### Assembling read data with Trinity ### """
    params:
        #**config['trinity']
        # optional parameters
        seqtype='fq',
        max_memory='64G',
        extra=""
    threads: 4
    log: join(LOGS_DIR, 'trinity/trinity.log')
    conda: "trinity-env.yaml"
    script: "trinity-wrapper.py"

rule rename_trinity_fasta:
    input: rules.trinity.output.fasta
    output: join(ASSEMBLY_DIR, BASE + '_trinity.fasta')
    log: join(LOGS_DIR, 'trinity/cp_assembly.log')
    shell: ("cp {input} {output}") 

rule rename_trinity_gene_trans_map:
    input: rules.trinity.output.gene_trans_map
    output: join(ASSEMBLY_DIR, BASE + '_trinity.fasta.gene_trans_map')
    log: join(LOGS_DIR, 'trinity/cp_gt_map.log')
    shell: ("cp {input} {output}") 


rule spades:
    input:
            left=expand(join(TRIM_DIR, '{sample}_1.trim.fq.gz'), sample=SAMPLES),
	    right=expand(join(TRIM_DIR, '{sample}_2.trim.fq.gz'), sample=SAMPLES),
            single=expand(join(TRIM_DIR, '{sample}_{end}.trim.fq.gz'), sample=SAMPLES, end=["1.se","2.se"]), 
    output:
        fasta = join(ASSEMBLY_DIR, "rnaspades", "transcripts.fasta"),
    message:
        """### Assembling read data with rnaSPADES ### """
    params:
    threads: 4
    log: join(LOGS_DIR, 'spades/spades.log')
    conda: "spades-env.yaml"
    script: "spades-wrapper.py"

rule rename_spades_fasta:
    input: rules.spades.output.fasta
    output: join(ASSEMBLY_DIR, BASE + '_spades.fasta')
    log: join(LOGS_DIR, 'spades/cp_assembly.log')
    shell: ("cp {input} {output}") 



# use fastqc & trimmomatic rules from eelpond
# assemblers! 
  # plass rule
  # megahit rule
#	
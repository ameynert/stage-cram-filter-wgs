#!/usr/bin/env nextflow

def helpMessage() {
    log.info"""
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run ameynert/stage-cram-filter-wgs --input 'bam_files/*.{bam,bai}' --outputdir filtered_cram_files

    Optional arguments:
      --input                       Path to input bam files on datastore
      --outdir                      The output directory where the results will be saved (filtered CRAM files)
      --targets                     Target BED file for filtering
      --padding                     Target padding
    """.stripIndent()
}

// Show help emssage
params.help = false
if (params.help){
    helpMessage()
    exit 0
}


// Defines reads and outputdir
params.input = "*.{bam,bai}"
params.outdir = 'filtered_cram_files'
params.targets = 'targets.bed'
params.padding = 0

// Header 
println "========================================================"
println "       STAGE_CRAM_FILTER    P I P E L I N E         "
println "========================================================"
println "['Pipeline Name']     = ameynert/stage-cram-filter-wgs"
println "['Pipeline Version']  = workflow.manifest.version"
println "['Input']             = $params.input"
println "['Output dir']        = $params.outdir"
println "['Targets']           = $params.targets"
println "['Padding']           = $params.padding"
println "['Working dir']       = workflow.workDir"
println "['Container Engine']  = workflow.containerEngine"
println "['Current home']      = $HOME"
println "['Current user']      = $USER"
println "['Current path']      = $PWD"
println "['Working dir']       = workflow.workDir"
println "['Script dir']        = workflow.projectDir"
println "['Config Profile']    = workflow.profile"
println "========================================================"

if (!params.input) {
    exit 1, "Input BAM files not specified"
}

if (!params.targets) {
    exit 1, "Target BED file not specified"
}

if (!params.outdir) {
    exit 1, "Output directory not specified"
}

/*
 * Create value channels for input files
 */
targets_ch = Channel.value(file(params.targets))

/*
 * Create a channel for input BAM files
 */
Channel
  .fromFilePairs( params.input, size: 2 ) { file->file.name.replaceAll(/.bam|.bai$/,'') }
  .ifEmpty { exit 1, "Cannot find any files matching ${params.input}\nNB: Path needs to be enclosed in quotes!\nNB: Path requires at least one * wildcard!" }
  .set { input_ch }


// Stage a BAM & its index BAI
process stage {

  input:
  set val(name), file(bam) from input_ch

  output:
  set val(name), file('staged/*') into bam_ch

  script:
  """
  mkdir staged
  rsync -avL ${bam} ./staged/
  """
}

// Subset the BAM file to the target regions and output reads
process subset {

  publishDir params.outdir, mode: 'copy'

  input:
  set val(name), file(bam) from bam_ch
  file(targets) from targets_ch

  output:
  set val(name), file('*.fastq.gz') into subset_ch

  script:
  """
  bazam -bam ${name}.bam -L ${targets} -pad ${params.padding} \
    -n ${task.cpus} -r1 ${name}_R1.fastq -r2 ${name}_R2.fastq
  gzip *.fastq
  """
}

// Calculate md5 checksums on the read files
process md5 {

  publishDir params.outdir, mode: 'copy'

  input:
  set val(name), file(fastq) from subset_ch

  output:
  file('*.md5') into md5_ch

  script:
  """
  md5sum ${name}_R1.fastq.gz > ${name}_R1.fastq.gz.md5
  md5sum ${name}_R2.fastq.gz > ${name}_R2.fastq.gz.md5
  """
}

workflow.onComplete { 
    println ( workflow.success ? "Done!" : "Oops .. something went wrong" )
    log.info "Pipeline Complete"
}


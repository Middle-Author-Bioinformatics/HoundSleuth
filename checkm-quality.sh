#!/bin/bash

if [ "$#" == 0 ] || [ $1 == "-h" ]; then
  printf "Usage:\t checkm-quality.sh fileExtension BinDirectory threads OutDirectory
Completion and redundancy results written to file: checkm_qaResults\n"
  exit
fi

OUTDIR=$4
THREADS=$3
BINDIR=$2
EXT=$1


checkm tree -t ${THREADS} -x ${EXT} ${BINDIR} ${OUTDIR}/checkm-output/
checkm tree_qa ${OUTDIR}/checkm-output/
checkm lineage_set ${OUTDIR}/checkm-output/ ${OUTDIR}/checkm-markers
checkm analyze -t ${THREADS} -x ${EXT} ${OUTDIR}/checkm-markers ${BINDIR} ${OUTDIR}/checkm-output/
checkm qa -t ${THREADS} -o 1 -f ${OUTDIR}/checkm_qaResults ${OUTDIR}/checkm-markers ${OUTDIR}/checkm-output/

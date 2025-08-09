#!/bin/bash

if [ "$#" == 0 ] || [ $1 == "-h" ]; then
  printf "Usage:\t checkm-quality.sh fileExtension BinDirectory threads OutDirectory
Completion and redundancy results written to file: checkm_qaResults\n"
  exit
fi

checkm tree -t $3 -x $1 $2 $4/checkm-output/
checkm tree_qa $4/checkm-output/
checkm lineage_set $4/checkm-output/ $4/checkm-markers
checkm analyze -t $3 -x $1 $4/checkm-output $2 $4/checkm-output/
checkm qa -t $3 -o 1 -f $4/checkm_qaResults $4/checkm-markers $4/checkm-output/

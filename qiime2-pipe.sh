#! /bin/bash
function usage() {
    cat <<USAGE
    Usage: $0 [-i input] [-o output] [-t thr] [-m meta] [--its]

    Options:
        -i, --input:      directory with reads
        -o, --output:     output folder name
        -m, --meta:       sample metadata file
        -t, --threads:    number of threads
        -a, --aux:        auxiliary data folder
        --its:            the provided data represents fungal ITS sequences

USAGE
    exit 1
}
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

ITS=false
THR=2
OUTPUT="qiime2_out"
while [ "$1" != "" ]; do
    case $1 in
    --its)
        ITS=true
        ;;
    -i | --input)
        shift
        INPUT=$1
        ;;
    -o | --output)
        shift
        OUTPUT=$1
        ;;
    -m | --meta)
        shift
        META=$1
        ;;
    -t | --thr)
        shift
        THR=$1
        ;;
    -a | --aux)
        shift
        AUX=$1
        ;;
    -h | --help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
    esac
    shift
done

if [[ ${INPUT} == "" ]]; then
    echo 'Please provide an input reads';
    exit 1;
fi


#eval "$(conda shell.bash hook)"
#conda activate qiime2-2019.7

mkdir -p ${OUTPUT}

# MAKING THE MANIFEST FILE
echo "sample-id	forward-absolute-filepath reverse-absolute-filepath" >> ${OUTPUT}/manifest
for i in ${INPUT}/*_R1.fastq.gz; do
  SAMPLE=$(basename ${i%_R1.*})
  echo ${SAMPLE} $PWD/${i%_R1.*}_R1.fastq.gz $PWD/${i%_R1.*}_R2.fastq.gz
  echo ${SAMPLE} $PWD/${i%_R1.*}_R1.fastq.gz $PWD/${i%_R1.*}_R2.fastq.gz >> ${OUTPUT}/manifest
done

cut -d '/' -f1- ${OUTPUT}/manifest > ${OUTPUT}/manifest2
tr " " "\t" < ${OUTPUT}/manifest2 > ${OUTPUT}/manifest3
mv ${OUTPUT}/manifest3 ${OUTPUT}/manifest
rm ${OUTPUT}/manifest2


# IMPORTING FASTQA INTO QIIME ARTIFACTS
qiime tools import --input-path ${OUTPUT}/manifest --output-path ${OUTPUT}/reads.qza --type 'SampleData[PairedEndSequencesWithQuality]' \
--input-format PairedEndFastqManifestPhred33V2

qiime demux summarize --i-data ${OUTPUT}/reads.qza --o-visualization ${OUTPUT}/reads.qzv

# DENOISING DATA AND CREATING REPRESENTATIVCE ASVS
qiime dada2 denoise-paired --i-demultiplexed-seqs ${OUTPUT}/reads.qza --p-trunc-len-f 280 --p-trunc-len-r 260 \
--p-trim-left-f 20 --p-trim-left-r 40 --p-n-threads ${THR} --o-representative-sequences ${OUTPUT}/rep-seqs-dada2.qza \
--o-table ${OUTPUT}/table-dada2.qza --o-denoising-stats ${OUTPUT}/stats-dada2.qza

qiime metadata tabulate --m-input-file ${OUTPUT}/stats-dada2.qza --o-visualization ${OUTPUT}/stats-dada2.qzv

# TAXONOMIC CLASSIFICATION OF REPRESENTATIVE SEQUENCES
if [[ ${ITS} == true ]]; then
    qiime feature-classifier classify-sklearn --i-classifier ${AUX}/unite-ver7-dynamic-classifier-01.12.2017.qza \
    --i-reads ${OUTPUT}/rep-seqs-dada2.qza --o-classification ${OUTPUT}/taxonomy.qza
else
    qiime feature-classifier classify-sklearn --i-classifier ${AUX}/classifier.qza \
    --i-reads ${OUTPUT}/rep-seqs-dada2.qza --o-classification ${OUTPUT}/taxonomy.qza
fi

qiime metadata tabulate --m-input-file ${OUTPUT}/taxonomy.qza --o-visualization ${OUTPUT}/taxonomy.qzv

# FITLERATION OF MITOCHONDRIA AND CHLOROPLASTS FROM THE DATA
qiime taxa filter-table --i-table ${OUTPUT}/table-dada2.qza --i-taxonomy ${OUTPUT}/taxonomy.qza --p-exclude mitochondria,chloroplast \
--o-filtered-table ${OUTPUT}/table-no-mitochondria-no-chloroplast.qza

# WRITING ASV TABLE
qiime tools export --input-path ${OUTPUT}/table-no-mitochondria-no-chloroplast.qza --output-path ${OUTPUT}/exported-dataset
biom convert -i ${OUTPUT}/exported-dataset/feature-table.biom -o ${OUTPUT}/exported-dataset/ASV_table.txt --to-tsv

# WRITING TAXONOMY TABLE
qiime tools export --input-path ${OUTPUT}/taxonomy.qza --output-path ${OUTPUT}/exported-dataset

# WRITING SEQUENCES TO FASTA
qiime tools export --input-path ${OUTPUT}/rep-seqs-dada2.qza --output-path ${OUTPUT}/exported-dataset/

# MAKING AN ALIGNMENT AND TREE
qiime alignment mafft --i-sequences ${OUTPUT}/rep-seqs-dada2.qza --p-n-threads 20 --o-alignment ${OUTPUT}/aligned-rep-seqs-dada2.qza
qiime phylogeny fasttree --i-alignment ${OUTPUT}/aligned-rep-seqs-dada2.qza --p-n-threads 20 --o-tree ${OUTPUT}/rep-seqs-tree.qza
qiime tools export --input-path ${OUTPUT}/rep-seqs-tree.qza --output-path ${OUTPUT}/exported-dataset/

# CREATING A DISTANCE MATRIX
qiime metadata distance-matrix --m-metadata-file ${META} --m-metadata-column numvar --o-distance-matrix ${OUTPUT}/distance-matrix.qza

#MAKING RAREFACTION CURVE
num_samples=$(awk '{print NF}' ${OUTPUT}/exported-dataset/ASV_table.txt | sort -nu | tail -n 1)
num_samples=$((${num_samples}-1))
echo ${num_samples}

#for i in $(seq 2 ${num_samples}); do cut -f${i} ${OUTPUT}/exported-dataset/ASV_table.txt | grep -v '#' | grep -v ${ORDER} | paste -sd+ | bc >> ${OUTPUT}/exported-dataset/depths; done
for i in $(seq 2 ${num_samples}); do cut -f$i ${OUTPUT}/exported-dataset/ASV_table.txt | grep -v '#' | grep -v '_' | paste -sd+ | bc >> ${OUTPUT}/exported-dataset/depths; done
min=`awk 'BEGIN{a=1000}{if ($1<a) a=$1 fi} END{print a}' ${OUTPUT}/exported-dataset/depths`
min=${min%.*}

qiime diversity alpha-rarefaction --i-table ${OUTPUT}/table-dada2.qza --p-max-depth ${min} \
--m-metadata-file ${META} --o-visualization ${OUTPUT}/alpha-rarefaction.qzv

## MAKING A TAXONOMIC BARPLOT
qiime taxa barplot --i-table ${OUTPUT}/table-dada2.qza --i-taxonomy ${OUTPUT}/taxonomy.qza --m-metadata-file ${META} \
--o-visualization ${OUTPUT}/taxa-bar-plots.qzv

# PERFORMING DIVERSITY ANALYSES
qiime diversity core-metrics --i-table ${OUTPUT}/table-dada2.qza --p-sampling-depth ${min} --m-metadata-file ${META} \
--p-n-jobs 20 --o-rarefied-table ${OUTPUT}/rarefied-table.qza --o-observed-otus-vector ${OUTPUT}/observed-otus-vector.qza \
--o-shannon-vector ${OUTPUT}/shannon-vector.qza --o-evenness-vector ${OUTPUT}/evenness-vector.qza --o-jaccard-distance-matrix \
${OUTPUT}/jaccard-distance-matrix.qza --o-bray-curtis-distance-matrix ${OUTPUT}/bray-curtis-distance-matrix.qza --o-jaccard-pcoa-results \
${OUTPUT}/jaccard-pcoa-results.qza --o-bray-curtis-pcoa-results ${OUTPUT}/curtis-pcoa-results.qza --o-jaccard-emperor ${OUTPUT}/jaccard-emperor.qzv \
--o-bray-curtis-emperor ${OUTPUT}/bray-curtis-emperor.qzv

#qiime diversity pcoa --i-distance-matrix ${OUTPUT}/distance-matrix.qza --o-pcoa ${OUTPUT}/pcoa.qza
#qiime tools export --input-path ${OUTPUT}/pcoa.qza --output-path ${OUTPUT}/pcoa.qzv

mkdir -p ${OUTPUT}/qiime2_artifacts
mkdir -p ${OUTPUT}/qiime2_visuals
mv ${OUTPUT}/*qza ${OUTPUT}/qiime2_artifacts/
mv ${OUTPUT}/*qzv ${OUTPUT}/qiime2_visuals/
rm ${OUTPUT}/manifest
mv ${META} ${OUTPUT}/
conda deactivate










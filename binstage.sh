#! /bin/bash

function usage() {
    cat <<USAGE

    Usage: $0 [-i input] [-o out] [-s snp] [-m min]

    Options:
        -i, --input:  input genome in FASTA format
        -o, --out:    output base name
        -s, --snp:    spraynpray output table
        -d, --depth:  coverage information from jgi_summarize_bam_contig_depths
        -m, --min:    minimum contig length

USAGE
    exit 1
}

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

SNP=false
MIN=300
OUT=binarena_input
DEPTH=false
while [ "$1" != "" ]; do
    case $1 in
    -i | --input)
        shift
        INPUT=$1
        ;;
    -o | --out)
        shift
        OUT=$1
        ;;
    -s | --snp)
        shift
        SNP=$1
        ;;
    -d | --depth)
        shift
        DEPTH=$1
        ;;
    -m | --min)
        shift
        MIN=$1
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
    echo 'Please provide input file';
    exit 1;
fi

SEQS=$(grep -c "^>" ${INPUT})

sequence_basics.py -i ${INPUT} -o ${OUT}.basic.tsv
count_kmers.py -i ${INPUT} -k 5 | reduce_dimension.py --pca --tsne --umap -o ${OUT}.k5 -f ${SEQS}
count_kmers.py -i ${INPUT} -k 4 | reduce_dimension.py --pca --tsne --umap -o ${OUT}.k4 -f ${SEQS}
count_kmers.py -i ${INPUT} -k 6 | reduce_dimension.py --pca --tsne --umap -o ${OUT}.k6 -f ${SEQS}

#count_kmers.py -i ${INPUT} -k 5 | reduce_dimension.py --pca --tsne --umap -o ${OUT}.k5
#count_kmers.py -i ${INPUT} -k 4 | reduce_dimension.py --pca --tsne --umap -o ${OUT}.k4
#count_kmers.py -i ${INPUT} -k 6 | reduce_dimension.py --pca --tsne --umap -o ${OUT}.k6

pca4=$(printf "ID\t4PC1\t4PC2")
pca5=$(printf "ID\t5PC1\t5PC2")
pca6=$(printf "ID\t6PC1\t6PC2")
tsne4=$(printf "ID\t4tsne1\t4tsne2")
tsne5=$(printf "ID\t5tsne1\t5tsne2")
tsne6=$(printf "ID\t6tsne1\t6tsne2")
umap4=$(printf "ID\t4UM1\t4UM2")
umap5=$(printf "ID\t5UM1\t5UM2")
umap6=$(printf "ID\t6UM1\t6UM2")


sed -i "1c $pca4" ${OUT}.k4.pca.tsv
sed -i "1c $pca5" ${OUT}.k5.pca.tsv
sed -i "1c $pca6" ${OUT}.k6.pca.tsv
sed -i "1c $tsne4" ${OUT}.k4.tsne.tsv
sed -i "1c $tsne5" ${OUT}.k5.tsne.tsv
sed -i "1c $tsne6" ${OUT}.k6.tsne.tsv
sed -i "1c $umap4" ${OUT}.k4.umap.tsv
sed -i "1c $umap5" ${OUT}.k5.umap.tsv
sed -i "1c $umap6" ${OUT}.k6.umap.tsv

#files=("${OUT}"*.tsv)
#cp "${files[0]}" binarena_input.tsv
#for ((i=1; i<${#files[@]}; i++)); do
#    join -t $'\t' -1 1 -2 1 binarena_input.tsv "${files[$i]}" > temp.tsv
#    mv temp.tsv ${OUT}.tsv
#done

mkdir -p ${OUT}_binarena
mv ${OUT}.*.tsv ${OUT}_binarena/
binarena-combine.py -i ${OUT}_binarena -o ${OUT}.tsv -b ${OUT}

if [[ ${SNP} != false ]]; then
    if [[ ${DEPTH} != false ]]; then
        binstager.py -b ${OUT}.tsv -o ${OUT}.taxa.depth.tsv -m ${MIN} -s ${SNP} -d ${DEPTH}
    else
        binstager.py -b ${OUT}.tsv -o ${OUT}.taxa.tsv -m ${MIN} -s ${SNP}
    fi
else
    if [[ ${DEPTH} != false ]]; then
        binstager.py -b ${OUT}.tsv -o ${OUT}.depth.tsv -m ${MIN} -d ${DEPTH}
    fi
fi

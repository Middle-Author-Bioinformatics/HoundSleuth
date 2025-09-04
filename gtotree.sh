#!/bin/bash
exec > >(tee -i /home/ark/MAB/houndsleuth/$1.log)
exec 2>&1

eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

KEY=$1
ID=$KEY
DIR=/home/ark/MAB/houndsleuth/${ID}
OUT=/home/ark/MAB/houndsleuth/completed/${ID}-results
NCBI_ASM_TSV="/home/ark/databases/ncbi_assembly_info.tsv"
NCBI2GENOMES="/home/ark/MAB/bin/HoundSleuth/ncbi2genomes.py"


mkdir -p ${OUT}

name=$(grep 'Name' ${DIR}/form-data.txt | cut -d ' ' -f2)
email=$(grep 'Email' ${DIR}/form-data.txt | cut -d ' ' -f2)
SCG=$(grep 'SCG' ${DIR}/form-data.txt | cut -d ' ' -f3)
ACC=$(grep 'Accessions' ${DIR}/form-data.txt | cut -d ' ' -f3)
genus=$(grep 'Genus' ${DIR}/form-data.txt | cut -d ' ' -f2)
species=$(grep 'Species' ${DIR}/form-data.txt | cut -d ' ' -f2)
strains=$(grep 'Strain' ${DIR}/form-data.txt | cut -d ' ' -f2)
echo $SCG
echo $ACC
echo

grep 'Genome' ${DIR}/form-data.txt | cut -d ' ' -f3 > ${OUT}/genomes.txt
grep 'Protein' ${DIR}/form-data.txt | cut -d ' ' -f3 > ${OUT}/proteomes.txt
grep 'GenBank' ${DIR}/form-data.txt | cut -d ' ' -f3 > ${OUT}/GBKs.txt

## Verify email
#result=$(python3 /home/ark/MAB/bin/HoundSleuth/check_email.py --email ${email})
#echo $result

# Set PATH to include Conda and script locations
export PATH="/home/ark/miniconda3/bin:/usr/local/bin:/usr/bin:/bin:/home/ark/MAB/bin/HoundSleuth:$PATH"
eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate gtotree

if [ $? -ne 0 ]; then
    echo "Error: Failed to activate Conda environment."
    exit 1
fi
sleep 5

# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
# Run GToTree
mkdir -p ${OUT}

while read file; do echo ${DIR}/$file >> ${OUT}/genome_paths.txt; done < ${OUT}/genomes.txt
while read file; do echo ${DIR}/$file >> ${OUT}/proteome_paths.txt; done < ${OUT}/proteomes.txt
while read file; do echo ${DIR}/$file >> ${OUT}/GBK_paths.txt; done < ${OUT}/GBKs.txt

# If a user uploaded an accessions file, capture the full path
if [[ -n "$ACC" && -s "${DIR}/${ACC}" ]]; then
    ACCESSIONS_UPLOADED="${DIR}/${ACC}"
fi

# If Genus is provided, use ncbi2genomes.py to pull accessions
if [[ -n "${genus}" ]]; then
    echo "Generating accessions from taxonomy: Genus='${genus}', Species='${species}', Strain='${strains}'"
    mkdir -p "${OUT}"
    : > "${ACCESSIONS_FROM_TAXA}"
    if [[ -f "${NCBI2GENOMES}" ]]; then
        python3 "${NCBI2GENOMES}" \
            -n "${NCBI_ASM_TSV}" \
            -g "${genus}" \
            -s "${species:-.}" \
            -t "${strains:-.}" \
            -o  "${OUT}/ncbi2genomes.matches.csv" \
            -o2 "${ACCESSIONS_FROM_TAXA}" || {
                echo "Warning: ncbi2genomes.py failed; continuing without taxonomy-derived accessions."
                : > "${ACCESSIONS_FROM_TAXA}"
            }
    else
        echo "Warning: ncbi2genomes.py not found at ${NCBI2GENOMES}; continuing without taxonomy-derived accessions."
        : > "${ACCESSIONS_FROM_TAXA}"
    fi
else
    : > "${ACCESSIONS_FROM_TAXA}"
fi

# Merge uploaded + taxonomy-derived accessions; uniq to avoid duplicates
: > "${ACCESSIONS_FINAL}"
if [[ -s "${ACCESSIONS_FROM_TAXA}" ]]; then
    awk 'NF' "${ACCESSIONS_FROM_TAXA}" >> "${ACCESSIONS_FINAL}"
fi
if [[ -n "${ACCESSIONS_UPLOADED}" && -s "${ACCESSIONS_UPLOADED}" ]]; then
    awk 'NF' "${ACCESSIONS_UPLOADED}" >> "${ACCESSIONS_FINAL}"
fi

# De-duplicate if we added anything
if [[ -s "${ACCESSIONS_FINAL}" ]]; then
    sort -u "${ACCESSIONS_FINAL}" -o "${ACCESSIONS_FINAL}"
    echo "Prepared merged accessions list: ${ACCESSIONS_FINAL}"
else
    echo "No accessions provided via taxonomy or uploaded file."
fi

# Prepare GToTree arguments
GToTree_CMD="GToTree"

if [ -s ${OUT}/proteome_paths.txt ]; then
    GToTree_CMD+=" -A ${OUT}/proteome_paths.txt"
else
    echo "Warning: Proteome file is empty, skipping this input."
fi

if [ -s ${OUT}/GBK_paths.txt ]; then
    GToTree_CMD+=" -g ${OUT}/GBK_paths.txt"
else
    echo "Warning: GenBank file is empty, skipping this input."
fi

if [ -s ${OUT}/genome_paths.txt ]; then
    GToTree_CMD+=" -f ${OUT}/genome_paths.txt"
else
    echo "Warning: Genome file is empty, skipping this input."
fi

# Use merged accessions if we have them
if [[ -s "${ACCESSIONS_FINAL}" ]]; then
    GToTree_CMD+=" -a ${ACCESSIONS_FINAL}"
else
    echo "Warning: No accessions (merged) available; skipping -a input."
fi

# Ensure at least one input file is provided
if [[ "$GToTree_CMD" == "GToTree" ]]; then
    echo "Error: All input files are empty. Skipping this iteration."
    conda deactivate
fi

# Add other fixed arguments
GToTree_CMD+=" -H ${SCG} -j 16 -M 16 -c 0.5 -G 0.2 -B -t -o ${OUT}/GTTout"

# Run the constructed GToTree command
echo "$GToTree_CMD"
eval "$GToTree_CMD"

# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
if [ $? -ne 0 ]; then
    echo "Error: GToTree failed."
    conda deactivate
    python3 /home/ark/MAB/bin/HoundSleuth/send_email.py \
        --sender binfo@midauthorbio.com \
        --recipient ${email} \
        --subject "GToTree failed..." \
        --attachment /home/ark/MAB/houndsleuth/$1.log \
        --body "Hi ${name},

        Unfortunately, it seems that this pipeline failed due to an unexpected error.

        Please forward this message to our team at binfo@midauthorbio.com, with the attached log file, so we can investigate the issue further.

        Thanks!
        Your Friendly Neighborhood Bioinformatician"
    exit 1
fi
conda deactivate
sleep 5

# Archive results
cp -r /home/ark/MAB/houndsleuth/completed/${ID}-results ./${ID}-results
tar -cf ${ID}-results.tar ${ID}-results && gzip ${ID}-results.tar

# Upload results to S3 and generate presigned URL
results_tar="${ID}-results.tar.gz"
s3_key="${ID}-results.tar.gz"
python3 /home/ark/MAB/bin/HoundSleuth/push.py --bucket binfo-dump --output_key ${s3_key} --source ${results_tar}
url=$(python3 /home/ark/MAB/bin/HoundSleuth/gen_presign_url.py --bucket binfo-dump --key ${s3_key} --expiration 86400)

mv ${ID}-results.tar.gz /home/ark/MAB/houndsleuth/completed/${ID}-results.tar.gz
rm -rf ${ID}-results

# Send email
python3 /home/ark/MAB/bin/HoundSleuth/send_email.py \
    --sender binfo@midauthorbio.com \
    --recipient ${email} \
    --subject "Your GToTree Results!" \
    --body "Hi ${name},

    Your GToTree results are available for download using the link below. The link will expire in 24 hours.

    ${url}

    Please visit github.com/AstrobioMike/GToTree for documentation.

    Cheers!
    Arkadiy"

if [ $? -ne 0 ]; then
    echo "Error: send_email.py failed."
    conda deactivate
    exit 1
fi

sleep 5

#sudo rm -rf ${DIR}

conda deactivate
echo "GToTree completed successfully."







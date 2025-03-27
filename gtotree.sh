#!/bin/bash
eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

exec > >(tee -i /home/ark/MAB/houndsleuth/gtotree_looper.log)
exec 2>&1

eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

KEY=$1
ID=$KEY
DIR=/home/ark/MAB/houndsleuth/${ID}
OUT=/home/ark/MAB/houndsleuth/completed/${ID}-results

name=$(grep 'Name' ${DIR}/form-data.txt | cut -d ' ' -f2)
email=$(grep 'Email' ${DIR}/form-data.txt | cut -d ' ' -f2)
SCG=$(grep 'SCG' ${DIR}/form-data.txt | cut -d ' ' -f3)
ACC=$(grep 'Accessions' ${DIR}/form-data.txt | cut -d ' ' -f3)
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

if [ -s ${DIR}/${ACC} ]; then
    GToTree_CMD+=" -a ${DIR}/${ACC}"
else
    echo "Warning: Accessions file is empty, skipping this input."
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







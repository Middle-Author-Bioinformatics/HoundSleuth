#!/bin/bash

exec > >(tee -i /home/ark/MAB/houndsleuth/$1.log)
exec 2>&1

eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

KEY=$1
ID=$KEY
DIR=/home/ark/MAB/houndsleuth/${ID}
OUT=/home/ark/MAB/houndsleuth/completed/${ID}-results


name=$(grep 'Name' ${DIR}/form-data.txt | cut -d ' ' -f2)
email=$(grep 'Email' ${DIR}/form-data.txt | cut -d ' ' -f2)
assembly=$(grep 'Assembly' ${DIR}/form-data.txt | cut -d ' ' -f3)
binplan=$(grep 'Bin' ${DIR}/form-data.txt | cut -d ' ' -f3)
echo $assembly

## Verify email
#result=$(python3 /home/ark/MAB/bin/HoundSleuth/check_email.py --email ${email})
#echo $result

# Set PATH to include Conda and script locations
export PATH="/home/ark/miniconda3/bin:/usr/local/bin:/usr/bin:/bin:/home/ark/MAB/bin/HoundSleuth:$PATH"
eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate checkm_env

if [ $? -ne 0 ]; then
    echo "Error: Failed to activate Conda environment."
    exit 1
fi
sleep 5


# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
# Run CheckM
mkdir -p ${OUT}
echo /home/ark/MAB/bin/HoundSleuth/plan2bin.py --fasta ${DIR}/${assembly} --tsv ${DIR}/${binplan} --outdir ${OUT}/bins
/home/ark/MAB/bin/HoundSleuth/plan2bin.py --fasta ${DIR}/${assembly} --tsv ${DIR}/${binplan} --outdir ${OUT}/bins
/home/ark/MAB/bin/HoundSleuth/checkm-quality.sh .fasta ${OUT}/bins 16
mv checkm_qaResults ${OUT}/bin_summary.txt

# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
if [ $? -ne 0 ]; then
    echo "Error: CheckM failed."
    conda deactivate
    python3 /home/ark/MAB/bin/HoundSleuth/send_email.py \
        --sender binfo@midauthorbio.com \
        --recipient ${email} \
        --subject "CheckM failed..." \
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
    --subject "Your CheckM Results!" \
    --body "Hi ${name},

    Your CheckM results are available for download using the link below. The link will expire in 24 hours.

    ${url}

    Please visit https://github.com/Ecogenomics/CheckM for documentation.

    Please reach out to ark@midauthorbio.com, or send us a note on https://midauthorbio.com/#contact if you have any questions.

    Thanks!
    MAB Team"

if [ $? -ne 0 ]; then
    echo "Error: send_email.py failed."
    conda deactivate
    exit 1
fi

sleep 5

#sudo rm -rf ${DIR}

conda deactivate
echo "CheckM completed successfully."




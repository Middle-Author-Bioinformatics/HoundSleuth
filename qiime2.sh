#!/bin/bash
eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

exec > >(tee -i /home/ark/MAB/houndsleuth/qiime2_looper.log)
exec 2>&1

eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

KEY=$1
ID=$KEY
DIR=/home/ark/MAB/houndsleuth/${ID}
OUT=/home/ark/MAB/houndsleuth/completed/${ID}-results

name=$(grep 'Name' ${DIR}/form-data.txt | cut -d ' ' -f2)
email=$(grep 'Email' ${DIR}/form-data.txt | cut -d ' ' -f2)
meta=$(grep 'Meta' ${DIR}/form-data.txt | cut -d ' ' -f3)
amp=$(grep 'Amplicon' ${DIR}/form-data.txt | cut -d ' ' -f3)

# Verify email
result=$(python3 /home/ark/MAB/bin/HoundSleuth/check_email.py --email ${email})
echo $result

# Set PATH to include Conda and script locations
export PATH="/home/ark/miniconda3/bin:/usr/local/bin:/usr/bin:/bin:/home/ark/MAB/bin/HoundSleuth:$PATH"
eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate qiime2-2019.7

if [ $? -ne 0 ]; then
    echo "Error: Failed to activate Conda environment."
    exit 1
fi
sleep 5

mkdir -p ${DIR}/reads
mv ${DIR}/*.f*q* ${DIR}/reads

# Run Qiime2
# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
if [[ ${amp} == "ITS" ]]; then
    qiime2-pipe.sh -i ${DIR}/reads -o ${OUT} -t 16 -m ${meta} -a /home/ark/MAB/bin/MAB_scripts/auxiliary --its
else
    qiime2-pipe.sh -i ${DIR}/reads -o ${OUT} -m ${meta} -t 16 -a /home/ark/MAB/bin/MAB_scripts/auxiliary
fi
# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
if [ $? -ne 0 ]; then
    echo "Error: Qiime2 failed."
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
    --sender qiime2@midauthorbio.com \
    --recipient ${email} \
    --subject "Your Qiime2 Results!" \
    --body "Hi ${name},

    Your Qiime2 results are available for download using the link below. The link will expire in 24 hours.

    ${url}

    Please visit https://qiime2.org/ for documentation.


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
echo "Qiime2 completed successfully."



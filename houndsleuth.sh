#!/bin/bash
eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

exec > >(tee -i /home/ark/MAB/houndsleuth/houndsleuth_looper.log)
exec 2>&1

eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate base  # Activate the base environment where `boto3` is installed

KEY=$1
ID=$KEY
DIR=/home/ark/MAB/houndsleuth/${ID}
OUT=/home/ark/MAB/houndsleuth/completed/${ID}-results


name=$(grep 'Name' ${DIR}/form-data.txt | cut -d ' ' -f2)
email=$(grep 'Email' ${DIR}/form-data.txt | cut -d ' ' -f2)
input=$(grep 'Input' ${DIR}/form-data.txt | cut -d ' ' -f3)
echo $input

# Verify email
result=$(python3 /home/ark/MAB/bin/HoundSleuth/check_email.py --email ${email})
echo $result

# Set PATH to include Conda and script locations
export PATH="/home/ark/miniconda3/bin:/usr/local/bin:/usr/bin:/bin:/home/ark/MAB/bin/HoundSleuth:$PATH"
eval "$(/home/ark/miniconda3/bin/conda shell.bash hook)"
conda activate houndsleuth39

if [ $? -ne 0 ]; then
    echo "Error: Failed to activate Conda environment."
    exit 1
fi
sleep 5


# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
# Run HoundsSleuth
mkdir -p ${OUT}
mkdir -p ${OUT}/binarena
mkdir -p ${OUT}/spraynpray

# checking if file exists:
if [ ! -f ${DIR}/${input}.blast ]; then
    /home/ark/MAB/bin/SprayNPray/spray-and-pray.py -g ${DIR}/${input} -out ${OUT}/spraynpray -ref /home/ark/databases/nr.dmnd --hits 1 -t 20
else
    /home/ark/MAB/bin/SprayNPray/spray-and-pray.py -g ${DIR}/${input} -out ${OUT}/spraynpray -ref /home/ark/databases/nr.dmnd --hits 1 -t 20 -blast ${DIR}/${input}.blast
fi


/home/ark/MAB/bin/HoundSleuth/binstage.sh -i ${DIR}/${input} -o ${OUT}/binarena/${input%.*} -D ${OUT}/binarena -s ${OUT}/spraynpray/spraynpray.csv -m 300

mv ${OUT}/binarena/${input%.*}.taxa.tsv ${OUT}/data_table_for_binarena.tsv

# **************************************************************************************************
# **************************************************************************************************
# **************************************************************************************************
if [ $? -ne 0 ]; then
    echo "Error: HoundSleuth failed."
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
    --sender StrainHound@midauthorbio.com \
    --recipient ${email} \
    --subject "Your HoundSleuth Results!" \
    --body "Hi ${name},

    Your HoundSleuth results are available for download using the link below. The link will expire in 24 hours.

    ${url}

    You can now navigate to https://main.d2fhjju1m7825g.amplifyapp.com/binarena-master/BinaRena.html and drag/drop the data_table_for_binarena.tsv file into the BinArena interface to visualize the results.

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
echo "MagicLamp completed successfully."




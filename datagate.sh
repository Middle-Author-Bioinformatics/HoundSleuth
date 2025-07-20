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
note=$(grep 'Note' ${DIR}/form-data.txt | cut -d ' ' -f3)
input=$(grep 'Input' ${DIR}/form-data.txt | cut -d ' ' -f3)

# Set PATH to include Conda and script locations
export PATH="/home/ark/miniconda3/bin:/usr/local/bin:/usr/bin:/bin:/home/ark/MAB/bin/HoundSleuth:$PATH"

# Send email
python3 /home/ark/MAB/bin/HoundSleuth/send_email.py \
    --sender binfo@midauthorbio.com \
    --recipient ark@midauthorbio.com \
    --subject "Datagate delivery!" \
    --body "Hi Arkadiy,

    ${name} has submitted a new Datagate package: ${KEY}

    Email: ${email}
    Note: ${note}
    Input: ${input}

    MAB Team"

if [ $? -ne 0 ]; then
    echo "Error: send_email.py failed."
#    conda deactivate
    exit 1
fi

sleep 5

#sudo rm -rf ${DIR}

#conda deactivate
echo "Megahit completed successfully."


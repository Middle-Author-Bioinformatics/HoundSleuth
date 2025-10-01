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

# Path to file containing valid bypass codes (CSV: email,code per line)
CODES_FILE="/home/ark/MAB/houndsleuth/valid_codes.txt"

mkdir -p ${OUT}

name=$(grep '^Name' ${DIR}/form-data.txt | cut -d ' ' -f2)
email=$(grep '^Email' ${DIR}/form-data.txt | cut -d ' ' -f2)
SCG=$(grep '^SCG' ${DIR}/form-data.txt | cut -d ' ' -f3)
ACC=$(grep '^Accessions' ${DIR}/form-data.txt | cut -d ' ' -f3)
genus=$(grep '^Genus' ${DIR}/form-data.txt | cut -d ' ' -f2)
species=$(grep '^Species' ${DIR}/form-data.txt | cut -d ' ' -f2)
strains=$(grep '^Strain' ${DIR}/form-data.txt | cut -d ' ' -f2)

# Read optional Code: line (anything after "Code: ")
code=$(sed -n 's/^Code: //p' "${DIR}/form-data.txt" | tr -d '\r' | head -n1)

# Normalize email and code for checking
email_norm=$(echo "${email}" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
code_trim=$(echo "${code}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

BYPASS_LIMIT=0
if [[ -n "${code_trim}" && -f "${CODES_FILE}" ]]; then
    # Check for exact match: (email,code)
    if awk -F',' -v e="${email_norm}" -v c="${code_trim}" '
        function trim(s){gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s}
        BEGIN{found=0}
        {
          em = tolower(trim($1));
          cd = trim($2);
          if(em==e && cd==c){found=1; exit 0}
        }
        END{ if(found==1) exit 0; else exit 1 }
    ' "${CODES_FILE}"; then
        echo "[INFO] Valid bypass code provided for ${email_norm}; skipping the 1000-accession subsample."
        BYPASS_LIMIT=1
    else
        # Check whether the code exists but for a different email (possible sharing attempt)
        if awk -F',' -v c="${code_trim}" '
            function trim(s){gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s}
            {
              cd = trim($2);
              if(cd==c){print trim($1); exit 0}
            }
            END{ exit 1 }
        ' "${CODES_FILE}" >/dev/null 2>&1; then
            owner_email=$(awk -F',' -v c="${code_trim}" '
                function trim(s){gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s}
                {
                  cd = trim($2);
                  if(cd==c){print tolower(trim($1)); exit 0}
                }
            ' "${CODES_FILE}")
            echo "[WARN] Code provided is assigned to a different email (${owner_email}); bypass denied for ${email_norm}."
        else
            echo "[INFO] Code provided but not found in codes list."
        fi
    fi
else
    if [[ -n "${code_trim}" ]]; then
        echo "[WARN] Code provided but codes file not found at ${CODES_FILE}."
    else
        echo "[INFO] No code provided."
    fi
fi

echo "SCG: $SCG"
echo "ACC: $ACC"
echo

grep '^Genome' ${DIR}/form-data.txt | cut -d ' ' -f3 > ${OUT}/genomes.txt
grep '^Protein' ${DIR}/form-data.txt | cut -d ' ' -f3 > ${OUT}/proteomes.txt
grep '^GenBank' ${DIR}/form-data.txt | cut -d ' ' -f3 > ${OUT}/GBKs.txt

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
    python3 "${NCBI2GENOMES}" \
        -n "${NCBI_ASM_TSV}" \
        -g "${genus}" \
        -s "${species:-.}" \
        -t "${strains:-.}" \
        -o  "${OUT}/ncbi.matches.tsv" \
        -o2 "${OUT}/ncbi.accessions.tsv"
else
    echo "No Genus provided; skipping taxonomy-derived accessions."
fi

# Merge uploaded + taxonomy-derived accessions; uniq to avoid duplicates
if [[ -s "${OUT}/ncbi.accessions.tsv" ]]; then
    # If there are more than 1000 lines, randomly subsample to 1000 unless bypass code was provided.
    total_lines=$(wc -l < "${OUT}/ncbi.accessions.tsv")
    echo "[INFO] Found ${total_lines} taxonomy-derived accessions."
    if (( total_lines > 1000 )) && (( BYPASS_LIMIT == 0 )); then
        echo "[INFO] More than 1000 accessions found; subsampling to 1000."
        shuf -n 1000 "${OUT}/ncbi.accessions.tsv" > "${OUT}/ncbi.accessions.sub.tsv"
    else
        if (( total_lines > 1000 )) && (( BYPASS_LIMIT == 1 )); then
            echo "[INFO] Bypass enabled; keeping all ${total_lines} taxonomy-derived accessions."
        fi
        cp "${OUT}/ncbi.accessions.tsv" "${OUT}/ncbi.accessions.sub.tsv"
    fi
    awk 'NF' "${OUT}/ncbi.accessions.sub.tsv" >> "${OUT}/ncbi.accessions.final.tsv"
fi

if [[ -s "${ACCESSIONS_UPLOADED}" ]]; then
    awk 'NF' "${ACCESSIONS_UPLOADED}" >> "${OUT}/ncbi.accessions.final.tsv"
fi

# De-duplicate if we added anything
if [[ -s "${OUT}/ncbi.accessions.final.tsv" ]]; then
    sort -u "${OUT}/ncbi.accessions.final.tsv" -o "${OUT}/ncbi.accessions.final.sorted.tsv"
    echo "Prepared merged accessions list: ${OUT}/ncbi.accessions.final.sorted.tsv"
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
if [[ -s "${OUT}/ncbi.accessions.final.sorted.tsv" ]]; then
    GToTree_CMD+=" -a ${OUT}/ncbi.accessions.final.sorted.tsv"
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

# remove the generated blast files
rm -f "${OUT}/ncbi.accessions.final.tsv" "${OUT}/ncbi.accessions.sub.tsv" "${OUT}/ncbi.accessions.tsv"
rm -f "${OUT}/genome_paths.txt" "${OUT}/proteome_paths.txt" "${OUT}/GBK_paths.txt"
rm -f "${OUT}/genomes.txt" "${OUT}/proteomes.txt" "${OUT}/GBKs.txt"

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

# Prepare note about subsampling for email body
if (( BYPASS_LIMIT == 1 )); then
    ACCESSION_NOTE="Your provided code was validated (tied to ${email_norm}) and allowed us to bypass the 1000-accession subsampling limit. All matched accessions were used."
else
    ACCESSION_NOTE="Please note if your selected Genus/Species names yielded more than 1000 accessions, a random subset of 1000 was used to generate the phylogenomic tree."
fi

# Send email
python3 /home/ark/MAB/bin/HoundSleuth/send_email.py \
    --sender binfo@midauthorbio.com \
    --recipient ${email} \
    --subject "Your GToTree Results!" \
    --body "Hi ${name},

    Your GToTree results are available for download using the link below. The link will expire in 24 hours.

    ${url}

    ${ACCESSION_NOTE}

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

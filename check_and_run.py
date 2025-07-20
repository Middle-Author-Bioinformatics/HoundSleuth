#!/usr/bin/env python3
import boto3
import os
import logging
import subprocess
import atexit
import sys
from datetime import datetime
from botocore.exceptions import NoCredentialsError, PartialCredentialsError

# Lock and log file paths
LOCK_FILE = '/home/ark/MAB/houndsleuth/houndsleuth.lock'
LOG_FILE = '/home/ark/MAB/houndsleuth/processed_folders.log'
RUN_LOG = '/home/ark/MAB/houndsleuth/houndsleuth_run.log'

# Initialize logging
logging.basicConfig(filename=RUN_LOG, level=logging.INFO, format='%(asctime)s %(message)s')

# Ensure lock file is removed on exit
def cleanup():
    if os.path.exists(LOCK_FILE):
        os.remove(LOCK_FILE)

# Check for existing lock file
if os.path.exists(LOCK_FILE):
    msg = "Another instance is already running. Exiting."
    print(msg)
    logging.info(msg)
    sys.exit(0)
else:
    open(LOCK_FILE, 'w').close()
    atexit.register(cleanup)

# S3 bucket name
BUCKET_NAME = 'breseqbucket'

# Prefix-to-script mapping
PREFIX_SCRIPT_MAP = {
    'pseudofinder-': '/home/ark/MAB/bin/HoundSleuth/pseudofinder.sh',
    'spraynpray-': '/home/ark/MAB/bin/HoundSleuth/spraynpray.sh',
    'gtotree-': '/home/ark/MAB/bin/HoundSleuth/gtotree.sh',
    'fegenie-': '/home/ark/MAB/bin/HoundSleuth/fegenie.sh',
    'mhcscan-': '/home/ark/MAB/bin/HoundSleuth/mhcscan.sh',
    # 'qiime2-': '/home/ark/MAB/bin/HoundSleuth/qiime2.sh',
    'megahit-': '/home/ark/MAB/bin/HoundSleuth/megahit.sh',
    'bakta-': '/home/ark/MAB/bin/HoundSleuth/bakta.sh',
    'checkm-': '/home/ark/MAB/bin/HoundSleuth/checkm.sh',
    'datagate-': '/home/ark/MAB/bin/HoundSleuth/datagate.sh',
    # 'quote-': '/home/ark/MAB/bin/HoundSleuth/quote.sh'
}

# Initialize S3 client (using default credentials)
s3 = boto3.client('s3')

def get_processed_folders():
    if not os.path.exists(LOG_FILE):
        return set()
    with open(LOG_FILE, 'r') as log:
        return set(line.strip() for line in log)

def log_processed_folders(folders):
    with open(LOG_FILE, 'a') as log:
        for folder in folders:
            log.write(f"{folder}\n")

def find_new_folders():
    new_folders = []
    processed_folders = get_processed_folders()
    checked = 0

    try:
        for prefix in PREFIX_SCRIPT_MAP.keys():
            response = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=prefix, Delimiter='/')
            if 'CommonPrefixes' not in response:
                continue

            for prefix_obj in response['CommonPrefixes']:
                folder_name = prefix_obj['Prefix'].rstrip('/')
                checked += 1
                if folder_name in processed_folders:
                    continue

                form_data_key = f"{folder_name}/form-data.txt"
                try:
                    s3.head_object(Bucket=BUCKET_NAME, Key=form_data_key)
                    print(f"Found new folder ready for processing: {folder_name}")
                    new_folders.append(folder_name)
                except s3.exceptions.ClientError:
                    continue

        logging.info(f"Checked {checked} folders. Found {len(new_folders)} new folders.")
        return new_folders

    except (NoCredentialsError, PartialCredentialsError) as e:
        logging.error(f"Error accessing S3: {e}")
        return []

def download_folder(bucket_name, folder_name, local_dir):
    paginator = s3.get_paginator('list_objects_v2')
    try:
        for page in paginator.paginate(Bucket=bucket_name, Prefix=folder_name):
            if 'Contents' not in page:
                print(f"No files found in folder {folder_name}.")
                return
            for obj in page['Contents']:
                key = obj['Key']
                local_path = os.path.join(local_dir, os.path.relpath(key, folder_name))
                os.makedirs(os.path.dirname(local_path), exist_ok=True)
                s3.download_file(bucket_name, key, local_path)
                print(f"Downloaded {key} to {local_path}")
    except Exception as e:
        logging.error(f"Error downloading folder {folder_name}: {e}")

def process_folder(folder_name):
    local_dir = f"/home/ark/MAB/houndsleuth/{folder_name}"
    print(f"Processing folder: {folder_name}")
    logging.info(f"Starting processing for folder: {folder_name}")
    download_folder(BUCKET_NAME, folder_name, local_dir)

    for prefix, script_path in PREFIX_SCRIPT_MAP.items():
        if folder_name.startswith(prefix):
            try:
                subprocess.run([script_path, folder_name], check=True)
                print(f"Successfully processed folder {folder_name} using {script_path}.")
                logging.info(f"Processed folder {folder_name} using {script_path}.")
                return
            except subprocess.CalledProcessError as e:
                logging.error(f"Error running {script_path} on folder {folder_name}: {e}")
                return

    logging.warning(f"No matching script found for folder {folder_name}.")

def main():
    logging.info("--- New run triggered ---")
    new_folders = find_new_folders()
    if new_folders:
        log_processed_folders(new_folders)
        logging.info(f"Queued {len(new_folders)} folders for processing.")
        for folder in new_folders:
            process_folder(folder)
    else:
        logging.info("No new folders to process.")

if __name__ == "__main__":
    main()

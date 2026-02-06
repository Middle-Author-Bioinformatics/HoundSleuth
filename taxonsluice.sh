#!/bin/bash

# Check if a directory argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <directory_path>"
    exit 1
fi

# Assign target directory and remove trailing slash if present
TARGET_DIR="${1%/}"

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

# Check if host_contamination directory exists inside, if not create it
CONTAM_DIR="$TARGET_DIR/host_contamination"
if [ ! -d "$CONTAM_DIR" ]; then
    echo "Creating directory: $CONTAM_DIR"
    mkdir -p "$CONTAM_DIR"
fi

echo "Processing files in '$TARGET_DIR'..."

# Loop through .fa files in the target directory
# We use find to avoid issues if no .fa files exist (glob expansion issues)
find "$TARGET_DIR" -maxdepth 1 -name "*.fa" | while read filepath; do

    filename=$(basename "$filepath")

    # Extract genus (assumes format: code.Genus.fa)
    # Fields: 1=code, 2=Genus, 3=fa
    genus=$(echo "$filename" | cut -d'.' -f2)

    # Get lineage using taxonkit
    # We echo just the genus to name2taxid
    lineage=$(echo "$genus" | taxonkit name2taxid 2>/dev/null | taxonkit lineage -i 2 2>/dev/null)

    # Check if lineage contains "Metazoa" OR "Embryophyta"
    if echo "$lineage" | grep -qE "Metazoa|Embryophyta"; then
        echo "[MOVING] Host/Multicellular: $filename ($genus)"
        mv "$filepath" "$CONTAM_DIR/"
    else
        # If it's single-celled, bacteria, fungi, or unclassified/unknown, keep it
        echo "[KEEPING] Microbial/Single-Celled: $filename ($genus)"
    fi
done

echo "Done."
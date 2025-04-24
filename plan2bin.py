#!/usr/bin/env python3

import argparse
import os
from collections import defaultdict
from Bio import SeqIO

def parse_tsv(tsv_file):
    contig_to_bin = {}
    with open(tsv_file, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                contig, bin_name = parts[0], parts[1] if parts[1] else None
                contig_to_bin[contig] = bin_name
            elif len(parts) == 1:
                contig_to_bin[parts[0]] = None
    return contig_to_bin

def write_bins(contig_to_bin, fasta_file, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    bin_seqs = defaultdict(list)
    unbinned = []

    for record in SeqIO.parse(fasta_file, "fasta"):
        contig_id = record.id
        bin_name = contig_to_bin.get(contig_id)
        if bin_name:
            bin_seqs[bin_name].append(record)
        else:
            unbinned.append(record)

    # Write binned sequences
    for bin_name, records in bin_seqs.items():
        bin_path = os.path.join(output_dir, f"{bin_name}.fasta")
        SeqIO.write(records, bin_path, "fasta")

    # Write unbinned sequences
    if unbinned:
        unbinned_path = os.path.join(output_dir, "unbinned.fasta")
        SeqIO.write(unbinned, unbinned_path, "fasta")

def main():
    parser = argparse.ArgumentParser(description="Separate contigs into bin files based on TSV map.")
    parser.add_argument("-t", "--tsv", required=True, help="Input TSV file with contig and bin name")
    parser.add_argument("-f", "--fasta", required=True, help="Input FASTA file with contigs")
    parser.add_argument("-o", "--outdir", required=True, help="Output directory to store binned FASTA files")

    args = parser.parse_args()

    contig_to_bin = parse_tsv(args.tsv)
    write_bins(contig_to_bin, args.fasta, args.outdir)

if __name__ == "__main__":
    main()
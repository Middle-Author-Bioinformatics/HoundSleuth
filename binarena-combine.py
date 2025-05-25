#!/usr/bin/env python
import re
import sys
import textwrap
import argparse
import os
import pandas as pd

parser = argparse.ArgumentParser(
    prog="binarena-combine.py",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=textwrap.dedent('''
    ************************************************************************
    ************************************************************************
    '''))

parser.add_argument('-i', type=str, help="input TSV directory", default="NA")
parser.add_argument('-o', type=str, help="output combined TSV file", default="NA")
parser.add_argument('-b', type=str, help="bin name", default="NA")

if len(sys.argv) == 1:
    parser.print_help(sys.stderr)
    sys.exit(0)

args = parser.parse_known_args()[0]


def combine_tsv_files(folder_path):
    basic_name = args.b + ".basic.tsv"
    # print(basic_name)
    basic_file_path = folder_path + "/" + args.b + ".basic.tsv"
    # print(basic_file_path)

    if not os.path.exists(basic_file_path):
        raise FileNotFoundError("basic.tsv file is missing from the folder.")

    basic_df = pd.read_csv(basic_file_path, sep='\t')
    combined_df = basic_df.copy()

    # Debugging
    print("Files in directory:", os.listdir(folder_path))
    print("Filtering for files containing:", args.b)

    BIN = os.path.basename(args.b)
    tsv_files = [f for f in os.listdir(folder_path) if f.endswith('.tsv') and f != basic_name and BIN in f]

    print("Matched TSV files:", tsv_files)

    for tsv_file in tsv_files:
        file_path = os.path.join(folder_path, tsv_file)
        print(file_path)
        dissimilarity_df = pd.read_csv(file_path, sep='\t')
        combined_df = pd.merge(combined_df, dissimilarity_df, on=combined_df.columns[0], how='left')

    return combined_df


# Example usage:
folder_path = args.i
combined_df = combine_tsv_files(folder_path)

# Save the combined data to a new TSV file
output_file_path = args.i + "/" + args.o
combined_df.to_csv(output_file_path, sep='\t', index=False)
print(f"Combined file saved to {output_file_path}")






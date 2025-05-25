#!/usr/bin/env python
from collections import defaultdict
import re
import argparse
import numpy as np
import sys
import textwrap
# from ArkTools import *

def Sum(ls):
    count = 0
    for i in ls:
        count += float(i)
    return count

def derep(ls):
    outLS = []
    for i in ls:
        if i not in outLS:
            outLS.append(i)
    return outLS


def ribosome(seq):
    NTs = ['T', 'C', 'A', 'G']
    stopCodons = ['TAA', 'TAG', 'TGA']
    Codons = []
    for i in range(4):
        for j in range(4):
            for k in range(4):
                codon = NTs[i] + NTs[j] + NTs[k]
                # if not codon in stopCodons:
                Codons.append(codon)

    CodonTable = {}
    AAz = "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"
    AAs = list(AAz)
    k = 0
    for base1 in NTs:
        for base2 in NTs:
            for base3 in NTs:
                codon = base1 + base2 + base3
                CodonTable[codon] = AAs[k]
                k += 1

    prot = []
    for j in range(0, len(seq), 3):
        codon = seq[j:j + 3]
        try:
            prot.append(CodonTable[codon])
        except KeyError:
            prot.append("")
    protein = ("".join(prot))
    return protein, CodonTable


def fasta(fasta_file):
    count = 0
    seq = ''
    header = ''
    Dict = defaultdict(lambda: defaultdict(lambda: 'EMPTY'))
    for i in fasta_file:
        i = i.rstrip()
        if re.match(r'^>', i):
            count += 1
            if count % 1000000 == 0:
                print(count)

            if len(seq) > 0:
                Dict[header] = seq
                header = i[1:]
                header = header.split(" ")[0]
                seq = ''
            else:
                header = i[1:]
                header = header.split(" ")[0]
                seq = ''
        else:
            seq += i
    Dict[header] = seq
    # print(count)
    return Dict


parser = argparse.ArgumentParser(
    prog="YfGenie.py",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=textwrap.dedent('''
    *******************************************************

    Developed by Arkadiy Garber;
    Arizona State University
    Please send comments and inquiries to agarber4@asu.edu

    *******************************************************
    '''))

parser.add_argument('-s', type=str, help="spraynpray output summary table",
                    default="")

parser.add_argument('-d', type=str, help="coverage information from jgi_summarize_bam_contig_depths", default="NA")

parser.add_argument('-b', type=str, help="binarena input table", default="")

parser.add_argument('-m', type=str, help="minimum contig depth", default=1000)

parser.add_argument('-o', type=str, help="output file", default="binstager")

if len(sys.argv) == 1:
    parser.print_help(sys.stderr)
    sys.exit(0)

args = parser.parse_known_args()[0]


summaryDict = defaultdict(lambda: '-')
summary = open(args.s)
for i in summary:
    ls = i.rstrip().split(",")
    if ls[1] != "contig_length":
        if float(ls[1]) > float(args.m):
            if len(ls[6]) > 1:
                taxa = (ls[6].split("; "))
                taxaDict = defaultdict(list)

                for j in taxa:
                    try:
                        tax = (j.split(" ")[1])
                        tax = tax.split(";")[0]
                    except IndexError:
                        tax = "unclassified"

                    taxaDict[tax].append(tax)

                taxaDict2 = defaultdict(lambda: '-')
                for j in taxaDict.keys():
                    taxaDict2[len(taxaDict[j])] = j

                v = list(taxaDict2.values())
                k = list(taxaDict2.keys())

                maxKey = (k[v.index(max(v))])
                winningTaxa = (taxaDict2[maxKey])
                if winningTaxa != "unclassified":
                    summaryDict[ls[0]] = winningTaxa
                else:
                    try:
                        taxaDict2.pop(maxKey)
                        v = list(taxaDict2.values())
                        k = list(taxaDict2.keys())
                        maxKey = (k[v.index(max(v))])
                        winningTaxa = (taxaDict2[maxKey])
                        summaryDict[ls[0]] = winningTaxa
                    except ValueError:
                        summaryDict[ls[0]] = "unclassified"

depthsDict = defaultdict(lambda: '-')
if args.d != "NA":
    depths = open(args.d)
    for i in depths:
        ls = i.rstrip().split("\t")
        depthsDict[ls[0]] = ls[2]
else:
    pass


out = open(args.o, "w")
binarena = open(args.b)
for i in binarena:
    ls = i.rstrip().split("\t")
    if ls[0] != "ID":
        if ls[0] in summaryDict.keys():
            out.write(i.rstrip() + "\t" + str(depthsDict[ls[0]]) + "\t" + str(summaryDict[ls[0]]) + "\n")
        else:
            pass
            # out.write(i.rstrip() + "\tadded_bin" + "\n")
    else:
        out.write(i.rstrip() + "\tdepth\ttaxa\n")
out.close()





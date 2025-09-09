#!/usr/bin/env python3

import argparse
import csv
import re
from Bio import SeqIO

def parse_args():
    parser = argparse.ArgumentParser(description="pull relevant rows from ncbi_assemly_info.tsv file")
    parser.add_argument("-n", "--ncbi", required=True, help="ncbi")
    parser.add_argument("-g", "--genera", required=True, help="genera")
    parser.add_argument("-s", "--species", required=False, help="species", default=".")
    parser.add_argument("-t", "--strain", required=False, help="strain", default=".")
    parser.add_argument("-o", "--output", required=True, help="Output CSV file")
    parser.add_argument("-o2", "--output2", required=True, help="Output CSV file")

    return parser.parse_args()

def load_fasta_sequences(fasta_file):
    return {record.id: str(record.seq) for record in SeqIO.parse(fasta_file, "fasta")}

def load_fasta_headers(fasta_file):
    return {record.id: record.description for record in SeqIO.parse(fasta_file, "fasta")}

def main():
    args = parse_args()

    # Open the NCBI assembly info file
    ncbi = open(args.ncbi, "r")

    out2 = open(args.output2, "w")

    out = open(args.output, "w")
    out.write("assembly\tbioproject\tbiosample\torganism\tstrain\tassembly_level\tgenome_rep\tseq_release\tasm_name\tasm_submitter\tgbk_accession\texcluded\tgroup\tgenome_size\tperc_gapped\tgc\treplicons\tscaffolds\tcontigs\tannotation_provider\tgenes\tcds\tnoncoding\n")
    out2_list = []  # collect accessions here to deduplicate later
    for i in ncbi:
        if re.match(r'^#', i):
            pass
        else:
            ls = i.rstrip().split("\t")
            assembly = ls[0]
            bioproject = ls[1]
            biosample = ls[2]
            organism = ls[7]
            strain = ls[8]
            assembly_level = ls[11]
            genome_rep = ls[13]
            seq_release = ls[14]
            asm_name = ls[15]
            asm_submitter = ls[16]
            gbk_accession = ls[17]
            excluded = ls[20]
            group = ls[24]
            genome_size = ls[25]
            perc_gapped = (1 - (float(ls[26]) / float(ls[25]))) * 100
            gc = ls[27]
            replicons = ls[28]
            scaffolds = ls[29]
            contigs = ls[30]
            annotation_provider = ls[32]
            genes = ls[34]
            cds = ls[35]
            noncoding = ls[36]
            if re.search(args.genera.lower(), organism.lower()): # genera is always provided as it is mandatory

                if len(args.species.lower()) > 1: # species name provided

                    if re.search(args.species.lower(), organism.lower()): # but does it match?

                        if len(args.strain) > 1: # strain name provided

                            if re.search(args.strain, i.rstrip()): # but does it match?

                                out.write(f"{assembly}\t{bioproject}\t{biosample}\t"
                                          f"{organism}\t{strain}\t{assembly_level}\t{genome_rep}\t"
                                          f"{seq_release}\t{asm_name}\t{asm_submitter}\t{gbk_accession}\t"
                                          f"{excluded}\t{group}\t{genome_size}\t{perc_gapped:.2f}\t{gc}\t"
                                          f"{replicons}\t{scaffolds}\t{contigs}\t"
                                          f"{annotation_provider}\t{genes}\t{cds}\t{noncoding}\n")

                                out2_list.append(assembly)

                            else:
                                continue

                        else:
                            out.write(f"{assembly}\t{bioproject}\t{biosample}\t"
                                      f"{organism}\t{strain}\t{assembly_level}\t{genome_rep}\t"
                                      f"{seq_release}\t{asm_name}\t{asm_submitter}\t{gbk_accession}\t"
                                      f"{excluded}\t{group}\t{genome_size}\t{perc_gapped:.2f}\t{gc}\t"
                                      f"{replicons}\t{scaffolds}\t{contigs}\t"
                                      f"{annotation_provider}\t{genes}\t{cds}\t{noncoding}\n")

                            out2_list.append(assembly)
                    else:
                        continue
                else:
                    out.write(f"{assembly}\t{bioproject}\t{biosample}\t"
                              f"{organism}\t{strain}\t{assembly_level}\t{genome_rep}\t"
                              f"{seq_release}\t{asm_name}\t{asm_submitter}\t{gbk_accession}\t"
                              f"{excluded}\t{group}\t{genome_size}\t{perc_gapped:.2f}\t{gc}\t"
                              f"{replicons}\t{scaffolds}\t{contigs}\t"
                              f"{annotation_provider}\t{genes}\t{cds}\t{noncoding}\n")

                    out2_list.append(assembly)

            else:
                continue


    # === Deduplicate accessions for output2 (prefer RefSeq GCF over GenBank GCA when paired) ===
    def _core_key(acc: str) -> str:
        m = re.match(r'^(GCF|GCA)_(\d+)(?:\.\d+)?$', acc)
        return m.group(2) if m else acc

    def _version(acc: str) -> int:
        m = re.match(r'^[A-Z]+_\d+(?:\.(\d+))?$', acc)
        return int(m.group(1)) if m and m.group(1) else -1

    # Map core -> set of observed accessions (e.g., {'GCF_000123.1','GCA_000123.1'})
    by_core = {}
    core_order = []  # preserve first-seen order of cores
    for acc in out2_list:
        core = _core_key(acc)
        if core not in by_core:
            by_core[core] = set()
            core_order.append(core)
        by_core[core].add(acc)

    # Choose one per core: prefer GCF_*; if multiple with same prefix, choose highest version
    def _pick_one(accs: set[str]) -> str:
        accs = list(accs)
        # Sort by: prefix preference (GCF first), then version descending, then original string
        def key(a):
            pref = 0 if a.startswith('GCF_') else (1 if a.startswith('GCA_') else 2)
            return (pref, -_version(a), a)
        accs.sort(key=key)
        return accs[0]

    unique_accessions = [_pick_one(by_core[c]) for c in core_order]

    # Write out the final deduped list
    out2.seek(0)
    out2.truncate(0)
    for acc in unique_accessions:
        out2.write(f"{acc}\\n")

if __name__ == "__main__":
    main()
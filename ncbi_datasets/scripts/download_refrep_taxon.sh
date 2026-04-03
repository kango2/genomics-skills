#!/usr/bin/env bash
set -euo pipefail

# download_refrep_taxon.sh
#
# End-to-end workflow:
# 1) datasets summary genome taxon -> JSONL
# 2) dataformat tsv genome -> assemblies.all.tsv
# 3) filter refseq-category to reference/representative -> assemblies.refrep.tsv
# 4) create accessions.txt
# 5) datasets download genome accession -> zip
# 6) unzip to outdir
# 7) manifest.tsv with metadata + local file paths

usage() {
  cat <<'EOF'
Usage:
  bash download_refrep_taxon.sh --taxon <TaxID|Name> [--levels <csv>] [--annotated] [--outdir <dir>] [--zipname <file.zip>]

Options:
  --taxon       TaxID (e.g. 9606) or taxon name (e.g. "Homo sapiens") [required]
  --levels      Comma-separated: complete,chromosome,scaffold,contig (default: complete,chromosome,scaffold,contig)
  --annotated   If set, restrict to annotated assemblies when downloading
  --outdir      Output directory (default: genomes_refrep)
  --zipname     Zip filename (default: genomes.refrep.zip or genomes.refrep.annotated.zip)
  -h, --help    Show help

Outputs (in --outdir):
  assemblies.all.tsv
  assemblies.refrep.tsv
  accessions.txt
  <zipname>
  extracted ncbi_dataset/...
  manifest.tsv
EOF
}

TAXON=""
LEVELS="complete,chromosome,scaffold,contig"
ONLY_ANNOTATED="false"
OUTDIR="genomes_refrep"
ZIPNAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --taxon)
      TAXON="${2:-}"; shift 2 ;;
    --levels)
      LEVELS="${2:-}"; shift 2 ;;
    --annotated)
      ONLY_ANNOTATED="true"; shift ;;
    --outdir)
      OUTDIR="${2:-}"; shift 2 ;;
    --zipname)
      ZIPNAME="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage; exit 2 ;;
  esac
done

if [[ -z "$TAXON" ]]; then
  echo "ERROR: --taxon is required" >&2
  usage
  exit 2
fi

# Determine zip name
if [[ -z "$ZIPNAME" ]]; then
  if [[ "$ONLY_ANNOTATED" == "true" ]]; then
    ZIPNAME="genomes.refrep.annotated.zip"
  else
    ZIPNAME="genomes.refrep.zip"
  fi
fi

mkdir -p "$OUTDIR"
WORK="$OUTDIR"
ALL_TSV="$WORK/assemblies.all.tsv"
REFREP_TSV="$WORK/assemblies.refrep.tsv"
ACCESSIONS="$WORK/accessions.txt"
MANIFEST="$WORK/manifest.tsv"

echo "==> 1) Summarizing assemblies for taxon: $TAXON"
datasets summary genome taxon "$TAXON" \
  --assembly-level "$LEVELS" \
  --as-json-lines \
| dataformat tsv genome \
  --fields accession,organism-name,organism-tax-id,assminfo-name,assminfo-level,refseq-category \
  > "$ALL_TSV"

echo "==> 2) Filtering to reference/representative (refseq-category)"
awk -F'\t' 'NR==1{print;next}
tolower($0) ~ /reference genome|representative genome/ {print}' "$ALL_TSV" > "$REFREP_TSV"

echo "==> 3) Creating accessions list"
cut -f1 "$REFREP_TSV" | tail -n +2 > "$ACCESSIONS"

COUNT=$(wc -l < "$ACCESSIONS" | tr -d ' ')
if [[ "$COUNT" == "0" ]]; then
  echo "ERROR: No accessions found after filtering. Check taxon/levels or refseq-category availability." >&2
  exit 1
fi
echo "    Found $COUNT assemblies"

echo "==> 4) Downloading assemblies by accession list (zip: $ZIPNAME)"
DL_ARGS=(download genome accession --inputfile "$ACCESSIONS" --include genome,rna,protein,cds,gff3,gtf --filename "$WORK/$ZIPNAME")
if [[ "$ONLY_ANNOTATED" == "true" ]]; then
  DL_ARGS+=(--annotated)
fi
datasets "${DL_ARGS[@]}"

echo "==> 5) Extracting zip"
# Clean any previous extracted dataset to avoid mixing contents
rm -rf "$WORK/ncbi_dataset"
unzip -q "$WORK/$ZIPNAME" -d "$WORK"

BASE="$WORK/ncbi_dataset/data"

if [[ ! -d "$BASE" ]]; then
  echo "ERROR: Expected extracted path not found: $BASE" >&2
  echo "Check zip structure and extraction." >&2
  exit 1
fi

echo "==> 6) Building manifest.tsv with local file paths"
printf "assembly_accession\ttax_id\tspecies_name\tassembly_name\tassembly_level\trefseq_category\tgenome_fna\trna_fna\tprotein_faa\tcds_fna\tgff3\tgtf\n" > "$MANIFEST"

# Build lookup table from REFREP_TSV:
# Columns: accession, organism-name, organism-tax-id, assminfo-name, assminfo-level, refseq-category
tail -n +2 "$REFREP_TSV" | awk -F'\t' '{print $1"\t"$3"\t"$2"\t"$4"\t"$5"\t"$6}' > "$WORK/meta.lookup.tsv"

while IFS=$'\t' read -r acc taxid spname aname alevel refcat; do
  asm_dir="$BASE/$acc"

  # Some assemblies may have different directory naming; if absent, skip with blanks
  if [[ ! -d "$asm_dir" ]]; then
    printf "%s\t%s\t%s\t%s\t%s\t%s\t\t\t\t\t\t\n" \
      "$acc" "$taxid" "$spname" "$aname" "$alevel" "$refcat" >> "$MANIFEST"
    continue
  fi

  genome_fna=$(ls -1 "$asm_dir"/*_genomic.fna 2>/dev/null | head -n1 || true)
  rna_fna=$(ls -1 "$asm_dir"/*_rna.fna 2>/dev/null | head -n1 || true)
  protein_faa=$(ls -1 "$asm_dir"/*_protein.faa 2>/dev/null | head -n1 || true)
  cds_fna=$(ls -1 "$asm_dir"/*_cds_from_genomic.fna 2>/dev/null | head -n1 || true)
  gff3=$(ls -1 "$asm_dir"/*.gff 2>/dev/null | head -n1 || true)
  gtf=$(ls -1 "$asm_dir"/*.gtf 2>/dev/null | head -n1 || true)

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$acc" "$taxid" "$spname" "$aname" "$alevel" "$refcat" \
    "$genome_fna" "$rna_fna" "$protein_faa" "$cds_fna" "$gff3" "$gtf" \
    >> "$MANIFEST"
done < "$WORK/meta.lookup.tsv"

echo "==> Done."
echo "Outputs:"
echo "  $ALL_TSV"
echo "  $REFREP_TSV"
echo "  $ACCESSIONS"
echo "  $WORK/$ZIPNAME"
echo "  $WORK/ncbi_dataset/ ..."
echo "  $MANIFEST"

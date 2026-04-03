# NCBI Datasets CLI (v2) — Codex Skill

This skill enables an agent (Codex) to **discover, filter, download, and manifest** NCBI assemblies for a taxon using the **NCBI Datasets CLI v2**:
- `datasets` (download + summaries)
- `dataformat` (JSONL → TSV/XLSX formatting)

Primary use-case:
- Download **all assemblies for a taxon**, filtered to **reference/representative**,
- Include (if available): **GTF, GFF3, cDNA (RNA), protein, CDS, genome FASTA**,
- Generate a **TSV manifest** with key metadata + **local file paths**,
- Support filtering by **assembly level**: `complete`, `chromosome`, `scaffold`, `contig`.

---

## Prerequisites

Install NCBI Datasets CLI v2 (`datasets`) and `dataformat` and ensure they're on `PATH`.

Also requires standard Unix tools:
- `bash`, `awk`, `cut`, `ls`, `head`, `tail`, `unzip`, `mkdir`, `rm`
- Optional: `jq` for JSONL inspection

Verify:
```bash
datasets --version
dataformat --version
```

---

## Directory layout in your `.agents` folder

Recommended placement:

```
~/.agents/
  ncbi_datasets/
    skills.md
    scripts/
      download_refrep_taxon.sh
```

If your agent runner expects a different convention, keep the **same relative structure** and adjust accordingly.

---

## Skill: What Codex should do (high level)

Given:
- `TAXON` = TaxID or taxon name (e.g., `9606` or `Homo sapiens`)
- Optional filters:
  - `LEVELS` subset of `complete,chromosome,scaffold,contig`
  - `ONLY_ANNOTATED` boolean (true → filter to assemblies that are annotated)
- Output paths:
  - `assemblies.all.tsv`
  - `assemblies.refrep.tsv`
  - `accessions.txt`
  - downloaded zip + extracted directory
  - `manifest.tsv` containing metadata + local file paths

Steps:
1. Use `datasets summary genome taxon ... --as-json-lines` and pipe into `dataformat tsv genome` to produce a metadata table.
2. Filter to **reference** or **representative** assemblies using the `refseq-category` column.
3. Create an accession list.
4. Download by accession list, using `--include genome,rna,protein,cds,gff3,gtf` (and `--annotated` if required).
5. Unzip to a deterministic folder.
6. Create `manifest.tsv` with:
   - `assembly_accession`
   - `tax_id`
   - `species_name`
   - `assembly_name`
   - `assembly_level`
   - `refseq_category`
   - local file paths for: genome FASTA, RNA FASTA, protein FASTA, CDS FASTA, GFF3, GTF

---

## Quick usage (script)

A ready-to-run script is provided at:

`~/.agents/ncbi_datasets/scripts/download_refrep_taxon.sh`

Example:

```bash
bash download_refrep_taxon.sh \
  --taxon 9606 \
  --levels complete,chromosome \
  --outdir genomes_refrep_9606
```

Only annotated assemblies:

```bash
bash download_refrep_taxon.sh \
  --taxon "Homo sapiens" \
  --levels complete,chromosome \
  --annotated \
  --outdir genomes_refrep_hs_annot
```

Outputs (in `--outdir`):
- `assemblies.all.tsv`
- `assemblies.refrep.tsv`
- `accessions.txt`
- `genomes.refrep.zip` (or `.annotated.zip`)
- extracted folder `ncbi_dataset/ ...`
- `manifest.tsv`

---

## Manual command templates (if you don’t want the script)

### 1) Summarize assemblies for a taxon (JSONL → TSV)
```bash
TAXON="9606"
LEVELS="complete,chromosome,scaffold,contig"

datasets summary genome taxon "$TAXON" \
  --assembly-level "$LEVELS" \
  --as-json-lines \
| dataformat tsv genome \
  --fields accession,organism-name,organism-tax-id,assminfo-name,assminfo-level,refseq-category \
  > assemblies.all.tsv
```

### 2) Filter to reference / representative
```bash
awk -F'\t' 'NR==1{print;next}
tolower($0) ~ /reference genome|representative genome/ {print}' assemblies.all.tsv \
> assemblies.refrep.tsv
```

### 3) Create accession list
```bash
cut -f1 assemblies.refrep.tsv | tail -n +2 > accessions.txt
```

### 4) Download assemblies (+ annotation & sequences where available)
```bash
datasets download genome accession \
  --inputfile accessions.txt \
  --include genome,rna,protein,cds,gff3,gtf \
  --filename genomes.refrep.zip
```

Only annotated assemblies (optional):
```bash
datasets download genome accession \
  --inputfile accessions.txt \
  --annotated \
  --include genome,rna,protein,cds,gff3,gtf \
  --filename genomes.refrep.annotated.zip
```

### 5) Unzip to deterministic folder
```bash
OUTDIR="genomes_refrep"
mkdir -p "$OUTDIR"
unzip -q genomes.refrep.zip -d "$OUTDIR"
```

### 6) Create `manifest.tsv` (metadata + local file paths)
Use the script’s manifest logic or adapt:

- Base extracted directory: `$OUTDIR/ncbi_dataset/data/<ASSEMBLY_ACCESSION>/`
- Expected file patterns per assembly:
  - `*_genomic.fna`
  - `*_rna.fna`
  - `*_protein.faa`
  - `*_cds_from_genomic.fna`
  - `*.gff` (GFF3)
  - `*.gtf`

---

## Notes and edge cases

- “Representative” is captured via **`refseq-category`** in the assembly report; not all taxa have both reference and representative genomes.
- If you do **not** use `--annotated`, some assemblies may lack `gff/gtf`; the manifest will contain blank fields for missing files.
- Large taxa can produce very large downloads. Consider adding additional filters (assembly level, annotated-only, or curated accession list).

---

## Troubleshooting

- If `dataformat` complains about fields, check available fields:
  ```bash
  dataformat tsv genome --help
  ```
- Inspect JSONL:
  ```bash
  datasets summary genome taxon 9606 --as-json-lines | head
  ```
- Confirm extracted structure:
  ```bash
  ls -R "$OUTDIR/ncbi_dataset/data" | head -n 50
  ```

---

## Script reference

See `scripts/download_refrep_taxon.sh` for a robust end-to-end implementation.

configfile: "config.yaml"

onsuccess:
    print("Workflow finished, no error")

onerror:
    print("An error occurred")

onstart:
    long_reads = config["long_reads"]
    fasta = config["fasta"]
    short_reads_1 = config["short_reads_1"]
    short_reads_2 = config["short_reads_2"]
    gtdbtk_folder = config["gtdbtk_folder"]
    busco_folder = config["busco_folder"]
    import os
    if long_reads == "none" and short_reads_1 == "none":
        sys.exit("Need at least one of long_reads, short_reads_1")
    if long_reads != "none" and not os.path.exists(long_reads):
        sys.exit("long_reads does not point to a file")
    if short_reads_1 != "none" and not os.path.exists(short_reads_1):
        sys.exit("short_reads_1 does not point to a file")
    if short_reads_2 != "none" and not os.path.exists(short_reads_2):
        sys.exit("short_reads_2 does not point to a file")
    if gtdbtk_folder != "none" and not os.path.exists(gtdbtk_folder):
        sys.stderr.write("gtdbtk_folder does not point to a folder\n")
    if busco_folder != "none" and not os.path.exists(busco_folder):
        sys.stderr.write("busco_folder does not point to a folder\n")


rule prepare_binning_files:
    input:
        fasta = config["fasta"],
    output:
        maxbin_coverage = "data/maxbin.cov.list",
        bams = "data/binning_bams/done",
        metabat_coverage = "data/coverm.cov"
    conda:
        "envs/coverm.yaml"
    threads:
        config["max_threads"]
    script:
        "scripts/get_coverage.py"


rule maxbin_binning:
    input:
        fasta = config["fasta"],
        maxbin_cov = "data/maxbin.cov.list"
    output:
        "data/maxbin2_bins/done"
    conda:
        "envs/maxbin2.yaml"
    shell:
        "mkdir -p data/maxbin2_bins && " \
        "run_MaxBin.pl -contig {input.fasta} -abund_list {input.maxbin_cov} -out data/maxbin2_bins/maxbin && " \
        "touch data/maxbin2_bins/done"


rule concoct_binning:
    input:
        fasta = config["fasta"],
        bam_done = "data/binning_bams/done"
    output:
        "data/concoct_bins/done"
    conda:
        "envs/concoct.yaml"
    threads:
        config["max_threads"]
    shell:
        "mkdir -p data/concoct_working && " \
        "cut_up_fasta.py {input.fasta} -c 10000 -o 0 --merge_last -b data/concoct_working/contigs_10K.bed > data/concoct_working/contigs_10K.fa &&" \
        "concoct_coverage_table.py data/concoct_working/contigs_10K.bed data/binning_bams/*.bam > data/concoct_working/coverage_table.tsv &&" \
        "concoct --threads {threads}  --composition_file data/concoct_working/contigs_10K.fa --coverage_file data/concoct_working/coverage_table.tsv -b data/concoct_working/ &&" \
        "merge_cutup_clustering.py data/concoct_working/clustering_gt1000.csv > data/concoct_working/clustering_merged.csv &&" \
        "mkdir -p data/concoct_bins &&" \
        "extract_fasta_bins.py {input.fasta} data/concoct_working/clustering_merged.csv --output_path data/concoct_bins/ &&" \
        "touch data/concoct_bins/done"


rule metabat_binning_2:
    input:
        coverage = "data/coverm.cov",
        fasta = config["fasta"],
    output:
        metabat_done = "data/metabat_bins_2/done",
        metabat_sspec = "data/metabat_bins_sspec/done",
        metabat_vspec = "data/metabat_bins_ssens/done",
        metabat_sense = "data/metabat_bins_sens/done"
    conda:
        "envs/metabat2.yaml"
    shell:
        "mkdir -p data/metabat_bins_2 && " \
        "metabat --seed 89 -i {input.fasta} -a {input.coverage} -o data/metabat_bins_2/binned_contigs && " \
        "touch data/metabat_bins_2/done && " \
        "metabat1 --seed 89 --sensitive -i {input.fasta} -a {input.coverage} -o data/metabat_bins_sens/binned_contigs && " \
        "touch data/metabat_bins_sens/done && " \
        "metabat1 --seed 89 --supersensitive -i {input.fasta} -a {input.coverage} -o data/metabat_bins_ssens/binned_contigs && " \
        "touch data/metabat_bins_ssens/done && " \
        "metabat1 --seed 89 --superspecific -i {input.fasta} -a {input.coverage} -o data/metabat_bins_sspec/binned_contigs && " \
        "touch data/metabat_bins_sspec/done"

rule das_tool:
    input:
        fasta = config["fasta"],
        metabat2_done = "data/metabat_bins_2/done",
        concoct_done = "data/concoct_bins/done",
        maxbin_done = "data/maxbin2_bins/done",
        metabat_sspec = "data/metabat_bins_sspec/done",
        metabat_ssens = "data/metabat_bins_ssens/done",
        metabat_sense = "data/metabat_bins_sens/done"
    output:
        das_tool_done = "data/das_tool_bins/done"
    conda:
        "envs/das_tool.yaml"
    threads:
        config["max_threads"]
    shell:
        "Fasta_to_Scaffolds2Bin.sh -i data/metabat_bins_2 -e fa > data/metabat_bins_2.tsv && " \
        "Fasta_to_Scaffolds2Bin.sh -i data/metabat_bins_sspec -e fa > data/metabta_bins_sspec.tsv && " \
        "Fasta_to_Scaffolds2Bin.sh -i data/metabat_bins_ssens -e fa > data/metabta_bins_ssens.tsv && " \
        "Fasta_to_Scaffolds2Bin.sh -i data/metabat_bins_sens -e fa > data/metabta_bins_sens.tsv && " \
        "Fasta_to_Scaffolds2Bin.sh -i data/concoct_bins -e fa > data/concoct_bins.tsv && " \
        "Fasta_to_Scaffolds2Bin.sh -i data/maxbin2_bins -e fasta > data/maxbin_bins.tsv && " \
        "DAS_Tool --search_engine diamond --write_bin_evals 1 --write_bins 1 -t {threads}" \
        " -i data/metabat_bins_2.tsv,data/metabta_bins_sspec.tsv,data/metabta_bins_ssens.tsv,data/metabta_bins_sens.tsv,data/concoct_bins.tsv,data/maxbin_bins.tsv" \
        " -c {input.fasta} -o data/das_tool_bins/das_tool && " \
        "touch data/das_tool_bins/done"

rule checkm:
    input:
        "data/das_tool_bins/done"
    output:
        "data/checkm.out"
    conda:
        "envs/checkm.yaml"
    threads:
        config["max_threads"]
    shell:
        'checkm lineage_wf -t {threads} -x fa data/das_tool_bins/das_tool_DASTool_bins data/checkm > data/checkm.out'

rule gtdbtk:
    input:
        "data/das_tool_bins/done"
    output:
        done = "data/gtdbtk/done"
    params:
        gtdbtk_folder = config['gtdbtk_folder']
    conda:
        "envs/gtdbtk.yaml"
    threads:
        config["max_threads"]
    shell:
        "export GTDBTK_DATA_PATH={params.gtdbtk_folder} && " \
        "gtdbtk classify_wf --cpus {threads} --extension fa --genome_dir data/das_tool_bins/das_tool_DASTool_bins --out_dir data/gtdbtk && touch data/gtdbtk/done"


rule busco:
    input:
        "data/das_tool_bins/done"
    output:
        done = "data/busco/done"
    params:
        busco_folder = config["busco_folder"]
    conda:
        "envs/busco.yaml"
    threads:
        config["max_threads"]
    shell:
        "mkdir -p data/busco && cd data/busco && minimumsize=500000 && " \
        "for file in ../das_tool_bins/das_tool_DASTool_bins/*.fa; do " \
        "actualsize=$(wc -c <\"$file\"); " \
        "if [ $actualsize -ge $minimumsize ]; then " \
        "run_busco -q -c {threads} -t bac_tmp.${{file:33:-3}} -i $file -o bacteria_odb9.${{file:39:-3}} -l {params.busco_folder}/bacteria_odb9 -m geno; " \
        "run_busco -q -c {threads} -t euk_tmp.${{file:33:-3}} -i $file -o eukaryota_odb9.${{file:39:-3}} -l {params.busco_folder}/eukaryota_odb9 -m geno; " \
        "run_busco -q -c {threads} -t emb_tmp.${{file:33:-3}} -i $file -o embryophyta_odb9.${{file:39:-3}} -l {params.busco_folder}/embryophyta_odb9 -m geno; " \
        "run_busco -q -c {threads} -t fun_tmp.${{file:33:-3}} -i $file -o fungi_odb9.${{file:39:-3}} -l {params.busco_folder}/fungi_odb9 -m geno; " \
        "run_busco -q -c {threads} -t met_tmp.${{file:33:-3}} -i $file -o metazoa_odb9.${{file:39:-3}} -l {params.busco_folder}/metazoa_odb9 -m geno; " \
        "run_busco -q -c {threads} -t pro_tmp.${{file:33:-3}} -i $file -o protists_ensembl.${{file:39:-3}} -l {params.busco_folder}/protists_ensembl -m geno; " \
        "fi; done && " \
        "cd ../../ && touch data/busco/done"

rule recover_mags:
    input:
        "data/das_tool_bins/done"
        "data/gtdbtk/done"
        "data/busco/done"
    output:
        "data/done"
from snakemake.utils import min_version
PANDOC = "pandoc --filter pantable --filter pandoc-crossref --citeproc -f markdown+mark"

configfile: "config/default.yaml"

min_version("8.10")


onsuccess:
    if "email" in config.keys():
        shell("echo "" | mail -s 'graph-eg5 succeeded' {config[email]}")
onerror:
    if "email" in config.keys():
        shell("echo "" | mail -s 'graph-eg5 failed' {config[email]}")

rule all:
    message: "Run entire analysis and compile report."
    input:
        "build/report.html",
        "build/report.pdf",
        "build/test.success"


rule run:
    message: "Runs the demo model."
    params:
        slope = config["slope"],
        x0 = config["x0"]
    output: "build/results.pickle"
    conda: "envs/default.yaml"
    script: "scripts/model.py"


rule plot:
    message: "Visualises the demo results."
    input:
        results = rules.run.output
    output: "build/plot.png"
    conda: "envs/default.yaml"
    script: "scripts/vis.py"


def pandoc_options(wildcards):
    suffix = wildcards["suffix"]
    if suffix == "html":
        return "--embed-resources --standalone --to html5"
    elif suffix == "pdf":
        return "--pdf-engine weasyprint"
    elif suffix == "docx":
        return []
    else:
        raise ValueError(f"Cannot create report with suffix {suffix}.")


rule report:
    message: "Compile report.{wildcards.suffix}."
    input:
        "report/literature.yaml",
        "report/report.md",
        "report/pandoc-metadata.yaml",
        "report/apa.csl",
        "report/reset.css",
        "report/report.css",
        rules.plot.output
    params: options = pandoc_options
    output: "build/report.{suffix}"
    wildcard_constraints:
        suffix = "((html)|(pdf)|(docx))"
    conda: "envs/report.yaml"
    shadow: "minimal"
    shell:
        """
        cd report
        ln -s ../build .
        {PANDOC} report.md  --metadata-file=pandoc-metadata.yaml {params.options} \
        -o ../build/report.{wildcards.suffix}
        """


rule dag_dot:
    output: temp("build/dag.dot")
    shell:
        "snakemake --rulegraph > {output}"


rule dag:
    message: "Plot dependency graph of the workflow."
    input: rules.dag_dot.output[0]
    # Output is deliberatly omitted so rule is executed each time.
    conda: "envs/dag.yaml"
    shell:
        "dot -Tpdf {input} -o build/dag.pdf"


rule clean: # removes all generated results
    message: "Remove all build results but keep downloaded data."
    run:
         import shutil

         shutil.rmtree("build")
         print("Data downloaded to data/ has not been cleaned.")


rule test:
    # To add more tests, do
    # (1) Add to-be-tested workflow outputs as inputs to this rule.
    # (2) Turn them into pytest fixtures in tests/test_runner.py.
    # (3) Create or reuse a test file in tests/my-test.py and use fixtures in tests.
    message: "Run tests"
    input:
        test_dir = "tests",
        tests = map(str, Path("tests").glob("**/test_*.py")),
        model_results = rules.run.output[0],
    log: "build/test-report.html"
    output: "build/test.success"
    conda: "./envs/test.yaml"
    script: "./tests/test_runner.py"

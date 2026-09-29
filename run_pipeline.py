#!/usr/bin/env python3
"""
run_pipeline.py
----------------
Runs the full bayesian-ideal-points-italy pipeline end to end, in order:

  1. Scraping        (01_scraping_18.py, 01_scraping_19.py)
  2. Preprocessing    (02_preprocessing_18.py, 02_preprocessing_19.py)
  3. MCMC estimation  (03_mcmc_18.R, 03_mcmc_19.R)
  4. Analysis         (04_analysis_18.R, 04_analysis_19.R)
  5. Switchers        (05_switchers.R)
  6. Knit report      (Markdown_File_v2.Rmd -> index.html)

Usage:
    python run_pipeline.py
    python run_pipeline.py --skip-scraping          # reuse existing dataset_replica_XVIII/XIX.csv
    python run_pipeline.py --parallel-mcmc           # run 03_mcmc_18.R and 03_mcmc_19.R concurrently
    python run_pipeline.py --only mcmc,analysis       # run only selected stages
    python run_pipeline.py --rscript "C:/Program Files/R/R-4.3.2/bin/Rscript.exe"

Each stage is only run if its expected output files are missing, unless
--force is passed. This lets you resume after an interruption without
redoing completed stages (the scraping scripts already resume on their own
via their internal checkpointing; this script adds the same idea at the
stage level).

Logs for every stage are written to ./pipeline_logs/<stage>.log, and a
summary is printed at the end with per-stage timing and pass/fail status.

Requirements: Python 3.9+, no third-party packages (uses only stdlib).
Assumes this script is placed in and run from the project root
(bayesian-ideal-points-italy/), alongside the .py/.R/.Rmd files.
"""

import argparse
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# --------------------------------------------------------------------------
# CONFIGURATION
# --------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent
LOG_DIR = PROJECT_ROOT / "pipeline_logs"

STAGES = {
    "scrape_18": {
        "label": "Scrape XVIII roll-call data",
        "cmd": [sys.executable, "01_scraping_18.py"],
        "outputs": ["dataset_replica_XVIII.csv"],
    },
    "scrape_19": {
        "label": "Scrape XIX roll-call data",
        "cmd": [sys.executable, "01_scraping_19.py"],
        "outputs": ["dataset_replica_XIX.csv"],
    },
    "preprocess_18": {
        "label": "Preprocess XVIII data",
        "cmd": [sys.executable, "02_preprocessing_18.py"],
        "outputs": ["matrice_18.csv", "sample_reduction_18.csv"],
        "depends_on": ["scrape_18"],
    },
    "preprocess_19": {
        "label": "Preprocess XIX data",
        "cmd": [sys.executable, "02_preprocessing_19.py"],
        "outputs": ["matrice_19.csv", "sample_reduction_19.csv"],
        "depends_on": ["scrape_19"],
    },
    "mcmc_18": {
        "label": "MCMC estimation — XVIII (slow, ~60-90 min)",
        "cmd": None,  # filled in at runtime with the resolved Rscript path
        "script": "03_mcmc_18.R",
        "outputs": ["session_18.RData", "sensitivity_18.RData"],
        "depends_on": ["preprocess_18"],
    },
    "mcmc_19": {
        "label": "MCMC estimation — XIX (slow, ~45-60 min)",
        "cmd": None,
        "script": "03_mcmc_19.R",
        "outputs": ["session_19.RData", "sensitivity_19.RData"],
        "depends_on": ["preprocess_19"],
    },
    "analysis_18": {
        "label": "Generate XVIII plots",
        "cmd": None,
        "script": "04_analysis_18.R",
        "outputs": [],  # renders plots to screen/device; no reliable file output to check
        "depends_on": ["mcmc_18"],
    },
    "analysis_19": {
        "label": "Generate XIX plots",
        "cmd": None,
        "script": "04_analysis_19.R",
        "outputs": [],
        "depends_on": ["mcmc_19"],
    },
    "switchers": {
        "label": "Cross-legislature switcher analysis",
        "cmd": None,
        "script": "05_switchers.R",
        "outputs": [],
        "depends_on": ["mcmc_18", "mcmc_19"],
    },
    "knit": {
        "label": "Knit final report (Rmd -> index.html)",
        "cmd": None,
        "script": None,  # handled specially: Rscript -e 'rmarkdown::render(...)'
        "outputs": ["index.html"],
        "depends_on": ["mcmc_18", "mcmc_19"],
    },
}

# Order matters: this is the execution sequence.
STAGE_ORDER = [
    "scrape_18", "scrape_19",
    "preprocess_18", "preprocess_19",
    "mcmc_18", "mcmc_19",
    "analysis_18", "analysis_19",
    "switchers",
    "knit",
]

MCMC_PARALLEL_GROUP = ["mcmc_18", "mcmc_19"]


# --------------------------------------------------------------------------
# HELPERS
# --------------------------------------------------------------------------

def find_rscript(explicit_path: str | None) -> str:
    """Locate the Rscript executable."""
    if explicit_path:
        if not Path(explicit_path).exists():
            sys.exit(f"ERROR: --rscript path does not exist: {explicit_path}")
        return explicit_path

    found = shutil.which("Rscript")
    if found:
        return found

    # Common Windows install locations, since the .Rproj file suggests
    # this project is normally run from RStudio on Windows.
    candidates = [
        r"C:\Program Files\R\R-4.4.1\bin\Rscript.exe",
        r"C:\Program Files\R\R-4.4.0\bin\Rscript.exe",
        r"C:\Program Files\R\R-4.3.2\bin\Rscript.exe",
    ]
    for c in candidates:
        if Path(c).exists():
            return c

    sys.exit(
        "ERROR: Rscript not found on PATH. Install R, or pass its location "
        "explicitly with --rscript \"C:/path/to/Rscript.exe\"."
    )


def outputs_exist(stage: dict) -> bool:
    outputs = stage.get("outputs", [])
    if not outputs:
        return False  # no way to check -> always considered "not done"
    return all((PROJECT_ROOT / f).exists() for f in outputs)


def run_stage(name: str, stage: dict, log_path: Path) -> tuple[bool, float]:
    """Run one stage, streaming output to both console and a log file."""
    print(f"\n{'=' * 70}")
    print(f"[{datetime.now().strftime('%H:%M:%S')}] STARTING: {stage['label']}")
    print(f"{'=' * 70}")

    start = time.time()
    with open(log_path, "w", encoding="utf-8") as log_f:
        proc = subprocess.run(
            stage["cmd"],
            cwd=PROJECT_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        log_f.write(proc.stdout or "")
        # Echo the tail of output to console so failures are visible immediately
        tail = (proc.stdout or "").splitlines()[-40:]
        print("\n".join(tail))

    elapsed = time.time() - start
    ok = proc.returncode == 0
    status = "OK" if ok else f"FAILED (exit code {proc.returncode})"
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {stage['label']}: {status} "
          f"({elapsed / 60:.1f} min). Full log: {log_path}")
    return ok, elapsed


def run_stage_parallel(names: list[str], stages: dict, log_dir: Path):
    """Run several R-script stages concurrently via subprocess.Popen."""
    print(f"\n{'=' * 70}")
    print(f"[{datetime.now().strftime('%H:%M:%S')}] STARTING IN PARALLEL: "
          f"{', '.join(stages[n]['label'] for n in names)}")
    print(f"{'=' * 70}")

    procs = {}
    log_files = {}
    starts = {}
    for n in names:
        log_path = log_dir / f"{n}.log"
        log_f = open(log_path, "w", encoding="utf-8")
        log_files[n] = log_f
        starts[n] = time.time()
        procs[n] = subprocess.Popen(
            stages[n]["cmd"],
            cwd=PROJECT_ROOT,
            stdout=log_f,
            stderr=subprocess.STDOUT,
            text=True,
        )

    results = {}
    # Poll until all are done, printing completions as they happen
    remaining = set(names)
    while remaining:
        time.sleep(5)
        for n in list(remaining):
            ret = procs[n].poll()
            if ret is not None:
                elapsed = time.time() - starts[n]
                ok = ret == 0
                results[n] = (ok, elapsed)
                status = "OK" if ok else f"FAILED (exit code {ret})"
                print(f"[{datetime.now().strftime('%H:%M:%S')}] "
                      f"{stages[n]['label']}: {status} ({elapsed / 60:.1f} min). "
                      f"Log: {log_dir / (n + '.log')}")
                remaining.discard(n)

    for f in log_files.values():
        f.close()

    return results


# --------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-scraping", action="store_true",
                         help="Skip scraping stages; requires dataset_replica_XVIII.csv "
                              "and dataset_replica_XIX.csv to already exist.")
    parser.add_argument("--force", action="store_true",
                         help="Re-run every stage even if its output files already exist.")
    parser.add_argument("--parallel-mcmc", action="store_true",
                         help="Run 03_mcmc_18.R and 03_mcmc_19.R at the same time. "
                              "Uses more RAM/CPU but roughly halves wall-clock time "
                              "for the slowest part of the pipeline.")
    parser.add_argument("--only", type=str, default=None,
                         help="Comma-separated list of stage names to run "
                              f"(choices: {', '.join(STAGE_ORDER)}). "
                              "Runs the full pipeline if omitted.")
    parser.add_argument("--rscript", type=str, default=None,
                         help="Path to the Rscript executable, if not on PATH.")
    args = parser.parse_args()

    LOG_DIR.mkdir(exist_ok=True)
    rscript = find_rscript(args.rscript)
    print(f"Using Rscript at: {rscript}")

    # Fill in R-based commands now that we know the Rscript path
    for name in ("mcmc_18", "mcmc_19", "analysis_18", "analysis_19", "switchers"):
        STAGES[name]["cmd"] = [rscript, STAGES[name]["script"]]
    STAGES["knit"]["cmd"] = [
        rscript, "-e",
        'rmarkdown::render("Markdown_File_v2.Rmd", output_file = "index.html")'
    ]

    # Work out which stages to actually run
    if args.only:
        selected = [s.strip() for s in args.only.split(",")]
        unknown = set(selected) - set(STAGE_ORDER)
        if unknown:
            sys.exit(f"ERROR: unknown stage name(s): {', '.join(unknown)}. "
                      f"Valid stages: {', '.join(STAGE_ORDER)}")
        run_order = [s for s in STAGE_ORDER if s in selected]
    else:
        run_order = list(STAGE_ORDER)

    if args.skip_scraping:
        run_order = [s for s in run_order if s not in ("scrape_18", "scrape_19")]
        for req in ("dataset_replica_XVIII.csv", "dataset_replica_XIX.csv"):
            if not (PROJECT_ROOT / req).exists():
                sys.exit(f"ERROR: --skip-scraping was passed but {req} is missing.")

    print(f"\nPipeline plan ({len(run_order)} stage(s)):")
    for s in run_order:
        print(f"  - {s}: {STAGES[s]['label']}")

    summary = []
    overall_start = time.time()

    i = 0
    while i < len(run_order):
        name = run_order[i]

        # Special case: if both MCMC stages are next in line and parallel
        # mode was requested, launch them together.
        if (args.parallel_mcmc
                and name in MCMC_PARALLEL_GROUP
                and i + 1 < len(run_order)
                and run_order[i + 1] in MCMC_PARALLEL_GROUP
                and run_order[i + 1] != name):
            pair = [name, run_order[i + 1]]
            to_run = [n for n in pair if args.force or not outputs_exist(STAGES[n])]
            skipped = [n for n in pair if n not in to_run]
            for n in skipped:
                print(f"\nSKIPPING {STAGES[n]['label']} — outputs already exist "
                      f"(use --force to re-run).")
                summary.append((n, "SKIPPED", 0.0))

            if to_run:
                results = run_stage_parallel(to_run, STAGES, LOG_DIR)
                any_failed = False
                for n, (ok, elapsed) in results.items():
                    summary.append((n, "OK" if ok else "FAILED", elapsed))
                    if not ok:
                        any_failed = True
                if any_failed:
                    print("\nOne or both MCMC stages failed. Stopping pipeline. "
                          "Check pipeline_logs/ for details.")
                    print_summary(summary, overall_start)
                    sys.exit(1)

            i += 2
            continue

        # Normal sequential stage
        stage = STAGES[name]
        if not args.force and outputs_exist(stage):
            print(f"\nSKIPPING {stage['label']} — outputs already exist "
                  f"(use --force to re-run).")
            summary.append((name, "SKIPPED", 0.0))
            i += 1
            continue

        log_path = LOG_DIR / f"{name}.log"
        ok, elapsed = run_stage(name, stage, log_path)
        summary.append((name, "OK" if ok else "FAILED", elapsed))

        if not ok:
            print(f"\nStage '{name}' failed. Stopping pipeline. "
                  f"See {log_path} for the full error output.")
            print_summary(summary, overall_start)
            sys.exit(1)

        i += 1

    print_summary(summary, overall_start)
    print(f"\nDone. If everything succeeded, the rendered report is at: "
          f"{PROJECT_ROOT / 'index.html'}")


def print_summary(summary, overall_start):
    total_elapsed = time.time() - overall_start
    print(f"\n{'=' * 70}")
    print("PIPELINE SUMMARY")
    print(f"{'=' * 70}")
    for name, status, elapsed in summary:
        mins = f"{elapsed / 60:.1f} min" if elapsed else "-"
        print(f"  {name:<16} {status:<10} {mins}")
    print(f"\nTotal wall-clock time: {total_elapsed / 60:.1f} min")


if __name__ == "__main__":
    main()

# Bayesian Ideal Point Estimation of the Italian Chamber of Deputies

Replication and extension of the Clinton, Jackman & Rivers (2004) ideal point
estimation framework applied to roll-call voting data from the Italian Chamber
of Deputies (Camera dei Deputati), covering the XVIII (2018–2022) and XIX
(2022–present) legislatures.

**Live report:** [lodovico-monteforte.github.io/bayesian-ideal-points-italy](https://lodovico-monteforte.github.io/bayesian-ideal-points-italy/)
— the rendered `index.html` in this repo is the knitted output of
`Markdown_File_v2.Rmd` and contains the full write-up with all plots. This
README documents the pipeline and how to reproduce it from raw data.

---

## What This Project Does

Roll-call votes record how each legislator voted (Yea/Nay) on each bill. The
key insight of Clinton et al. (2004) is that these binary outcomes can be
modelled as a Bayesian probit, where the probability of a Yea vote depends
on the distance between a legislator's latent ideological position (ideal
point) and the implied position of the bill. By estimating this model via
Gibbs sampling, we recover a one-dimensional left-right ideological map of the
entire chamber from voting behaviour alone — without using any prior knowledge
of party affiliation.

The project covers the full pipeline: data collection via SPARQL, preprocessing,
MCMC estimation, convergence diagnostics, and analysis including a novel
cross-legislature comparison of party switchers.

---

## Repository Structure

```
bayesian-ideal-points-italy/
│
├── 01_scraping_18.py          # Scrapes XVIII roll-call data from dati.camera.it
├── 01_scraping_19.py          # Scrapes XIX roll-call data from dati.camera.it
├── 02_preprocessing_18.py     # Cleans and reshapes XVIII data into vote matrix
├── 02_preprocessing_19.py     # Cleans and reshapes XIX data into vote matrix
│
├── 03_mcmc_18.R               # MCMC estimation for XVIII legislature
├── 03_mcmc_19.R               # MCMC estimation for XIX legislature
├── 04_analysis_18.R           # All plots for XVIII legislature
├── 04_analysis_19.R           # All plots for XIX legislature
├── 05_switchers.R             # Cross-legislature party switcher analysis
│
├── Markdown_File_v2.Rmd       # Full analysis report (knits to index.html)
├── index.html                 # Rendered report — served via GitHub Pages
├── index_files/figure-html/   # Figures embedded in the rendered report
│
├── BAYESIAN REPLICA.Rproj     # RStudio project file
└── README.md
```

> **Note:** The data files (`matrice_18.csv`, `matrice_19.csv`,
> `dataset_replica_XVIII.csv`, `dataset_replica_XIX.csv`) and the saved MCMC
> sessions (`session_18.RData`, `session_19.RData`) are not tracked in this
> repository due to file size. Instructions to reproduce them are below.

---

## Reproducing the Analysis

### Requirements

**Python (≥ 3.9):**
```
pandas
SPARQLWrapper
```
Install with:
```bash
pip install pandas SPARQLWrapper
```

**R (≥ 4.2):**
```
pscl, ggplot2, coda, tidyr, dplyr, patchwork, knitr, scales, ggrepel
```
Install with:
```r
install.packages(c("pscl", "ggplot2", "coda", "tidyr", "dplyr",
                   "patchwork", "knitr", "scales", "ggrepel"))
```

### Step-by-step

**1. Clone the repository and open the RStudio project**
```bash
git clone https://github.com/lodovico-monteforte/bayesian-ideal-points-italy.git
```
Open `BAYESIAN REPLICA.Rproj` in RStudio. This sets the working directory
automatically — all scripts use relative paths.

**2. Scrape the data** (≈ 30–60 min per legislature)
```bash
python 01_scraping_18.py
python 01_scraping_19.py
```
Both scripts support automatic resume if interrupted.

**3. Preprocess**
```bash
python 02_preprocessing_18.py
python 02_preprocessing_19.py
```
Outputs: `matrice_18.csv`, `matrice_19.csv`, `sample_reduction_18.csv`,
`sample_reduction_19.csv`.

**4. Run MCMC estimation** (≈ 60–90 min per legislature)
```r
source("03_mcmc_18.R")
source("03_mcmc_19.R")
```
Outputs: `session_18.RData`, `session_19.RData`, `sensitivity_18.RData`,
`sensitivity_19.RData`.

> ⚠️ These scripts are intended to be run **once**. Results are saved to
> `.RData` files and loaded by all subsequent scripts.

**5. Generate the plots** (loads saved sessions, no re-estimation)
```r
source("04_analysis_18.R")
source("04_analysis_19.R")
source("05_switchers.R")
```

**6. Knit the report**

Open `Markdown_File_v2.Rmd` in RStudio and click Knit, or run:
```r
rmarkdown::render("Markdown_File_v2.Rmd", output_file = "index.html")
```
The knitted `index.html` is what's served at the Pages link above.

---

## Data Source

Roll-call voting data is sourced from the Italian Chamber of Deputies open
data portal: [dati.camera.it](https://dati.camera.it/). The portal exposes
data via a public SPARQL endpoint. Only final votes (`votazioneFinale = 1`)
are used, excluding procedural votes.

---

## Method

The model follows Clinton, Jackman & Rivers (2004). Each legislator $i$ has
a latent ideal point $x_i \in \mathbb{R}$. For each roll call $j$, the
probability of a Yea vote is:

$$P(y_{ij} = 1) = \Phi(x_i \beta_j - \alpha_j)$$

where $\beta_j$ is a discrimination parameter (how strongly vote $j$ separates
left from right) and $\alpha_j$ is a difficulty parameter (overall propensity
to vote Yea). Estimation is via Gibbs sampling using the Albert–Chib data
augmentation for probit models.

Identification is achieved by fixing two anchor legislators:
- **Fratoianni Nicola** (far-left anchor, fixed at $-1$)
- **Lollobrigida Francesco** (far-right anchor, fixed at $+1$)

### Diagnostics and robustness checks produced by the analysis scripts

| Check | What it shows |
|---|---|
| Sensitivity analysis (tight / default / flat bill priors) | Whether ideal point estimates are stable across prior specifications |
| Geweke convergence diagnostics | Whether MCMC chains for ideal points and bill parameters have converged |
| CI width vs. votes cast | Whether posterior uncertainty shrinks as expected with more voting data |
| β/α discrimination-difficulty map | Which votes are most ideologically loaded vs. procedurally uninformative |

---

## Key Findings

- The **XIX legislature** produces a clean left-right separation consistent
  with the known political landscape. The governing coalition (FdI, Lega, FI)
  clusters compactly on the right; the opposition (PD-IDP, AVS, M5S) occupies
  the left.
- The **XVIII legislature** is considerably noisier due to three distinct
  governments forming over its course, most notably the reversal of M5S from
  government to opposition.
- A cross-legislature comparison of party switchers suggests that ideal
  point estimates partially reflect coalition dynamics rather than pure
  individual ideology: several legislators show non-trivial shifts in
  estimated position after changing party.

---

## Reference

Clinton, J., Jackman, S., & Rivers, D. (2004). The Statistical Analysis of
Roll Call Data. *American Political Science Review*, 98(2), 355–370.
https://doi.org/10.1017/S0003055404001194

---

## Author

**Lodovico Monteforte**
M.Sc. QEM — Models and Methods of Quantitative Economics
Ca' Foscari University of Venice
lodovico.monteforte@gmail.com

"""
02_preprocessing_18.py
----------------------
Cleans and reshapes the raw roll-call dataset for the XVIII Legislature (2018-2022)
into a legislator x vote matrix suitable for ideal point estimation in R.

Input:  dataset_replica_XVIII.csv  (produced by 01_scraping_18.py)
Output: matrice_18.csv             (legislator x vote binary matrix)
        sample_reduction_18.csv    (sample reduction report for the Rmd)

Usage: python 02_preprocessing_18.py

Requirements: pandas
"""

import pandas as pd
import os

# ------------ LOAD RAW DATA
path_file = "dataset_replica_XVIII.csv"

if not os.path.exists(path_file):
    print(f"Error: {path_file} not found. Run 01_scraping_18.py first.")
    exit()

df = pd.read_csv(path_file, low_memory=False)
print(f"Raw dataset: {df.shape[0]} rows, {df['voto_id'].nunique()} votes, "
      f"{df[['cognome','nome']].drop_duplicates().shape[0]} legislators")

# ------------ STEP 1: BINARY ENCODING OF VOTES
# Only Yea (1) and Nay (0) are retained. Abstentions and absences become NaN.
mapping = {'Favorevole': 1, 'Contrario': 0}
df['voto_num'] = df['voto'].map(mapping)

# ------------ STEP 2: STANDARDISE PARTY NAMES
# Raw party names from the SPARQL endpoint include dates and full legal names.
# We replace them with short standard labels.
party_mapping = {
    "MOVIMENTO 5 STELLE (M5S) (27.03.2018":                                          "M5S",
    "PARTITO DEMOCRATICO (PD) (27.03.2018":                                           "PD",
    "LEGA - SALVINI PREMIER (LEGA) (27.03.2018":                                      "Lega",
    "FORZA ITALIA - BERLUSCONI PRESIDENTE (FI) (27.03.2018":                          "FI",
    "FRATELLI D'ITALIA (FDI) (27.03.2018":                                            "FdI",
    "LIBERI E UGUALI-ARTICOLO 1-SINISTRA ITALIANA (LEU-ART 1-SI) (10.04.2018":       "LEU-ART1-SI",
    "MISTO (MISTO) (23.03.2018":                                                      "MISTO",
    "ITALIA VIVA-ITALIA C'E' (IV-IC'E') (19.09.2019":                                "IV",
    "INSIEME PER IL FUTURO - IMPEGNO CIVICO (IPF-IC) (21.06.2022":                   "IPF-IC",
    "CORAGGIO ITALIA (CI) (27.05.2021-23.06.2022)":                                   "CI",
}

df['partito'] = df['partito'].replace(party_mapping)

# ------------  LEGISLATOR ID
# We use SURNAME + NAME as a unique identifier.
# Legislators who switched party mid-legislature are collapsed onto a single ID,
# retaining their full voting record but assigned to their LAST party of affiliation.
# This is a simplification: in rare extreme cases (e.g. far-left to far-right switch)
# it may create outliers, but such cases should be uncommon and do not affect model mechanics
# since ideal points depend on votes, not party labels.
df['deputato_id'] = df['cognome'] + " " + df['nome']

# ------------  BUILD VOTE MATRIX
matrice_full = df.pivot_table(
    index='deputato_id',
    columns='voto_id',
    values='voto_num',
    aggfunc='max'
)

# ------------ ATTACH METADATA
info_deputati = df.sort_values('voto_id').groupby('deputato_id').agg({
    'cognome': 'first',
    'nome':    'first',
    'partito': 'last'   # last party affiliation
})

info_deputati['legis.name'] = info_deputati['cognome'] + " " + info_deputati['nome']
info_deputati = info_deputati.drop(columns=['nome', 'cognome'])

matrice_finale = pd.concat([info_deputati, matrice_full], axis=1)

# ------------  SAMPLE REDUCTION REPORT
# The R ideal() function drops:
# (a) votes where the minority side is < lop % of total (default lop = 0.05)
# (b) legislators with no recorded votes
# We compute equivalent statistics here.
# Note: the actual filtering is handled automatically by the ideal() function in R
# (via the dropList and lop arguments). The calculations below approximate what the R package drops
# but do not modify the output matrix in any way.

n_legislators_raw = len(matrice_finale)
n_votes_raw       = matrice_full.shape[1]

# Legislators with zero votes recorded
zero_vote_legs = (matrice_full.notna().sum(axis=1) == 0).sum()

# Votes failing the lop = 0.05 filter
def lop_score(col):
    yea   = (col == 1).sum()
    nay   = (col == 0).sum()
    total = yea + nay
    return min(yea, nay) / total if total > 0 else 0

lop_scores    = matrice_full.apply(lop_score, axis=0)
dropped_votes = (lop_scores < 0.05).sum()

print(f"\n--- Sample Reduction Report (XVIII) ---")
print(f"Legislators (raw):          {n_legislators_raw}")
print(f"Legislators (zero votes):   {zero_vote_legs}")
print(f"Votes (raw):                {n_votes_raw}")
print(f"Votes dropped (lop < 0.05): {dropped_votes}")
print(f"Votes kept:                 {n_votes_raw - dropped_votes}")

summary = pd.DataFrame([{
    'legislature':          'XVIII',
    'legislators_raw':      n_legislators_raw,
    'legislators_no_votes': zero_vote_legs,
    'votes_raw':            n_votes_raw,
    'votes_dropped_lop':    dropped_votes,
    'votes_kept':           n_votes_raw - dropped_votes
}])
summary.to_csv("sample_reduction_18.csv", index=False)
print("Sample reduction report saved to: sample_reduction_18.csv")

# ------------ STEP 7: SAVE MATRIX
matrice_finale.to_csv("matrice_18.csv", index=False)
print(f"\nDone! Matrix saved to: matrice_18.csv")
print(f"Shape: {matrice_finale.shape[0]} legislators x {matrice_full.shape[1]} votes")

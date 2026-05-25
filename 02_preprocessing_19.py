"""
02_preprocessing_19.py
----------------------
Cleans and reshapes the raw roll-call dataset for the XIX Legislature (2022-present)
into a legislator x vote matrix suitable for ideal point estimation in R.

Input:  dataset_replica_XIX.csv   (produced by 01_scraping_19.py)
Output: matrice_19.csv            (legislator x vote binary matrix)
        sample_reduction_19.csv   (sample reduction report for the Rmd)

Usage: python 02_preprocessing_19.py

Requirements: pandas
"""

import pandas as pd
import os

# ------------ LOAD RAW DATA
path_file = "dataset_replica_XIX.csv"

df = pd.read_csv("dataset_replica_XIX.csv", low_memory=False)
print(df['partito'].unique())

if not os.path.exists(path_file):
    print(f"Error: {path_file} not found. Run 01_scraping_19.py first.")
    exit()

df = pd.read_csv(path_file, low_memory=False)
print(f"Raw dataset: {df.shape[0]} rows, {df['voto_id'].nunique()} votes, "
      f"{df[['cognome','nome']].drop_duplicates().shape[0]} legislators")

# ------------  BINARY ENCODING OF VOTES
# Only Yea (1) and Nay (0) are retained. Abstentions and absences become NaN.
mapping = {'Favorevole': 1, 'Contrario': 0}
df['voto_num'] = df['voto'].map(mapping)

# ------------  STANDARDISE PARTY NAMES
# Raw party names from the SPARQL endpoint include dates and full legal names.
# We replace them with short standard labels.
party_mapping = {
    "MOVIMENTO 5 STELLE (M5S) (18.10.2022":                                                                         "M5S",
    "PARTITO DEMOCRATICO - ITALIA DEMOCRATICA E PROGRESSISTA (PD-IDP) (18.10.2022":                                 "PD-IDP",
    "LEGA - SALVINI PREMIER (LEGA) (18.10.2022":                                                                     "Lega",
    "FORZA ITALIA - BERLUSCONI PRESIDENTE - PPE (FI-PPE) (18.10.2022":                                              "FI",
    "FRATELLI D'ITALIA (FDI) (18.10.2022":                                                                           "FdI",
    "MISTO (MISTO) (18.10.2022":                                                                                     "MISTO",
    "ITALIA VIVA-IL CENTRO-RENEW EUROPE (IV-C-RE) (20.11.2023":                                                     "IV-C-RE",
    "AZIONE-POPOLARI EUROPEISTI RIFORMATORI-RENEW EUROPE (AZ-PER-RE) (18.10.2022":                                  "AZ-PER-RE",
    "NOI MODERATI (NOI CON L'ITALIA, CORAGGIO ITALIA, UDC E ITALIA AL CENTRO)-MAIE-CENTRO POPOLARE (NM(N-C-U-I)M-CP) (27.10.2022": "NM",
    "ALLEANZA VERDI E SINISTRA (AVS) (27.10.2022":                                                                  "AVS",
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

# ------------  ATTACH METADATA
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
# We compute equivalent statistics here for transparency.

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

print(f"\n--- Sample Reduction Report (XIX) ---")
print(f"Legislators (raw):          {n_legislators_raw}")
print(f"Legislators (zero votes):   {zero_vote_legs}")
print(f"Votes (raw):                {n_votes_raw}")
print(f"Votes dropped (lop < 0.05): {dropped_votes}")
print(f"Votes kept:                 {n_votes_raw - dropped_votes}")

summary = pd.DataFrame([{
    'legislature':          'XIX',
    'legislators_raw':      n_legislators_raw,
    'legislators_no_votes': zero_vote_legs,
    'votes_raw':            n_votes_raw,
    'votes_dropped_lop':    dropped_votes,
    'votes_kept':           n_votes_raw - dropped_votes
}])
summary.to_csv("sample_reduction_19.csv", index=False)
print("Sample reduction report saved to: sample_reduction_19.csv")

# ------------  SAVE MATRIX
matrice_finale.to_csv("matrice_19.csv", index=False)
print(f"\nDone! Matrix saved to: matrice_19.csv")
print(f"Shape: {matrice_finale.shape[0]} legislators x {matrice_full.shape[1]} votes")

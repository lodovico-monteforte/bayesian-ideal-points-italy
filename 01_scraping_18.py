"""
01_scraping_18.py
-----------------
Scrapes final roll-call votes from the Italian Chamber of Deputies (XVIII Legislature, 2018-2022)
via the SPARQL endpoint at dati.camera.it.

Output: dataset_replica_XVIII.csv (one row per legislator per vote)

Usage: python 01_scraping_18.py
Note:  Full scrape takes ~30-60 minutes depending on connection speed.
       The script supports automatic resume if interrupted.

Requirements: SPARQLWrapper, pandas
"""

import pandas as pd
import os
import time
import socket
from SPARQLWrapper import SPARQLWrapper, JSON

# ------------ CONFIGURATION
endpoint_url = "https://dati.camera.it/sparql"
file_output  = "dataset_replica_XVIII.csv"

sparql = SPARQLWrapper(endpoint_url)
socket.setdefaulttimeout(60)  # Prevents blocking if the server is slow

def run_query(query):
    """Run a SPARQL query with up to 3 retries on failure."""
    for attempt in range(3):
        sparql.setQuery(query)
        sparql.setReturnFormat(JSON)
        try:
            results = sparql.query().convert()
            return results["results"]["bindings"]
        except Exception as e:
            print(f"Attempt {attempt + 1} failed: {e}. Retrying...")
            time.sleep(5)
    return []

# ------------  RETRIEVE LIST OF FINAL VOTES
# The Camera dei Deputati exposes its data via a SPARQL endpoint.
# We query only "votazioneFinale" (final votes), excluding procedural votes.
query_votes = """
PREFIX ocd: <http://dati.camera.it/ocd/>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
SELECT DISTINCT ?data ?numeroVotazione WHERE {
  ?votazione a ocd:votazione ;
             ocd:rif_leg <http://dati.camera.it/ocd/legislatura.rdf/repubblica_18> ;
             ocd:votazioneFinale 1 ;
             dc:date ?data ;
             dc:identifier ?numeroVotazione .
} ORDER BY ?data
"""

print("Retrieving list of final votes...")
votes = run_query(query_votes)
df_list = pd.DataFrame([{
    "data": v["data"]["value"],
    "id":   v["numeroVotazione"]["value"]
} for v in votes])

if df_list.empty:
    print("Error: no votes found. Check your connection.")
    exit()

print(f"Found {len(df_list)} final votes.")

# ------------  RESUME CHECK
# If the output file already exists, skip votes already downloaded.
# This should allow the script to resume from where it left off if interrupted.
already_downloaded = set()
if os.path.exists(file_output):
    try:
        df_existing = pd.read_csv(file_output, usecols=['voto_id'])
        already_downloaded = set(df_existing['voto_id'].unique().astype(str))
        print(f"Resume detected: {len(already_downloaded)} votes already downloaded.")
    except Exception:
        print("Starting new file.")

# ------------  DOWNLOAD VOTE-LEVEL DATA
# For each vote, retrieve each legislator's name, vote expression, and party group
# at the time of the vote (using date filters to handle mid-legislature party switches).
print(f"Starting download for {len(df_list)} votes...")

for index, row in df_list.iterrows():
    curr_id = str(row['id'])

    if curr_id in already_downloaded:
        continue  # Skip if already downloaded

    print(f"Downloading vote {curr_id} dated {row['data']} ({index + 1}/{len(df_list)})...")

    query_detail = f"""
    PREFIX ocd: <http://dati.camera.it/ocd/>
    PREFIX dc: <http://purl.org/dc/elements/1.1/>
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

    SELECT DISTINCT ?cognome ?nome ?espressione ?gruppo_label WHERE {{
      ?votazione dc:identifier '{curr_id}' .
      ?voto ocd:rif_votazione ?votazione ;
             ocd:rif_deputato ?deputato ;
             dc:type ?espressioneUri .
      ?deputato foaf:surname ?cognome ; foaf:firstName ?nome ; ocd:aderisce ?adesione .
      ?adesione ocd:rif_gruppoParlamentare ?gruppo ; ocd:startDate ?start .
      ?gruppo rdfs:label ?gruppo_label .
      FILTER (?start <= '{row['data']}')
      OPTIONAL {{ ?adesione ocd:endDate ?end . }}
      FILTER (!BOUND(?end) || ?end >= '{row['data']}')
      BIND(REPLACE(STR(?espressioneUri), "http://dati.camera.it/ocd/votazione.rdf/", "") AS ?espressione)
    }}
    """

    data = run_query(query_detail)

    if data:
        rows = [{
            "data":    row['data'],
            "voto_id": curr_id,
            "cognome": d["cognome"]["value"],
            "nome":    d["nome"]["value"],
            "voto":    d["espressione"]["value"],
            "partito": d["gruppo_label"]["value"]
        } for d in data]

        df_temp = pd.DataFrame(rows)
        file_exists = os.path.exists(file_output)
        df_temp.to_csv(file_output, mode='a', index=False, header=not file_exists)

    time.sleep(0.5)  # We don't want to seem a DoS attempt

print(f"\nDone! Output saved to: {file_output}")

# ------------ STEP 4: QUICK SANITY CHECK
df = pd.read_csv(file_output, low_memory=False)
print(f"\nDataset contains {df.shape[0]} rows and {df.shape[1]} columns.")
print("\nFirst rows:")
print(df.head())
print("\nLast rows:")
print(df.tail())
print("\nTop 5 legislators by number of votes recorded:")
print(df.groupby(['cognome', 'nome']).size().sort_values(ascending=False).head(5))

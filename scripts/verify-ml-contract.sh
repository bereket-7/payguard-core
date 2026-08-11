#!/usr/bin/env bash
# Verifies the ML feature contract JSON matches FeatureVector.FEATURE_COLUMNS in fraud-engine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/services/payguard-fraud-model-training/contracts/feature-contract-v1.json"
JAVA_COLUMNS="$ROOT/services/payguard-fraud-engine/src/main/java/com/payguard/fraud/scoring/FeatureVector.java"

if [[ ! -f "$CONTRACT" ]]; then
  echo "ERROR: missing contract file: $CONTRACT"
  exit 1
fi

if [[ ! -f "$JAVA_COLUMNS" ]]; then
  echo "ERROR: missing FeatureVector.java: $JAVA_COLUMNS"
  exit 1
fi

python3 - <<'PY' "$CONTRACT" "$JAVA_COLUMNS"
import json
import re
import sys

contract_path, java_path = sys.argv[1], sys.argv[2]
contract = json.load(open(contract_path))
expected = [feature["name"] for feature in contract["features"]]

java = open(java_path).read()
match = re.search(r'List\.of\(([^)]+)\)', java)
if not match:
    raise SystemExit("ERROR: could not parse FEATURE_COLUMNS from FeatureVector.java")

actual = [part.strip().strip('"') for part in match.group(1).split(",")]
if actual != expected:
    print("ERROR: feature column mismatch")
    print("  contract:", expected)
    print("  java:    ", actual)
    raise SystemExit(1)

print("OK: feature contract aligned (" + ", ".join(expected) + ")")
PY

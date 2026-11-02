#!/usr/bin/env bash
# Reproduce el análisis estático de Slither sobre los contratos del laboratorio.
# Requisitos: slither-analyzer 0.11.6 y solc 0.8.28 (vía solc-select):
#   pip install slither-analyzer==0.11.6 solc-select
#   solc-select install 0.8.28 && solc-select use 0.8.28
#
# Se analiza una copia de src/ sin foundry.toml para compilar con solc directamente
# (crytic-compile aún no lee el formato de build-info de forge 1.8).
set -euo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$LAB/analisis/slither"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -r "$LAB/src" "$WORK/"
ln -s "$LAB/lib" "$WORK/lib"
mkdir -p "$OUT"
cd "$WORK"
export SOLC_VERSION=0.8.28
for f in src/C*/*.sol; do
  base="$OUT/$(basename "$(dirname "$f")")_$(basename "$f" .sol)"
  rm -f "$base.json"
  slither "$f" \
    --solc-remaps "@openzeppelin/contracts/=lib/openzeppelin/" \
    --solc-args "--evm-version cancun --optimize --optimize-runs 200" \
    --filter-paths "lib/" --json "$base.json" > "$base.txt" 2>&1 || true
done
# Comprobación específica de proxies (colisión de almacenamiento, caso C4).
for v in Vulnerable:ProxyVulnerable:LogicaVulnerable Fixed:ProxyFixed:LogicaFixed; do
  IFS=: read -r file proxy logic <<< "$v"
  slither-check-upgradeability "src/C4-delegatecall-proxies/$file.sol" "$logic" \
    --proxy-name "$proxy" \
    --solc-remaps "@openzeppelin/contracts/=lib/openzeppelin/" \
    --solc-args "--evm-version cancun" \
    > "$OUT/C4-upgradeability_$file.txt" 2>&1 || true
done
echo "Resultados en $OUT"

#!/usr/bin/env bash
set -euo pipefail

# Exports a whisper.cpp encoder Core ML bundle (.mlmodelc).
# Usage:
#   ./scripts/export-whisper-coreml.sh base.en
#
# Output (inside the whisper.cpp checkout):
#   whisper.cpp/models/ggml-<MODEL>-encoder.mlmodelc

MODEL="${1:-base.en}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${ROOT}/.whisper.cpp"

if [[ ! -d "${WORKDIR}/.git" ]]; then
  echo "Cloning whisper.cpp into ${WORKDIR}"
  git clone https://github.com/ggml-org/whisper.cpp.git "${WORKDIR}"
fi

cd "${WORKDIR}"

if [[ ! -d ".venv" ]]; then
  echo "Creating python venv"
  python3 -m venv .venv
fi

echo "Activating venv + installing deps"
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install ane_transformers openai-whisper coremltools

echo "Generating Core ML model for: ${MODEL}"
./models/generate-coreml-model.sh "${MODEL}"

OUT="models/ggml-${MODEL}-encoder.mlmodelc"
if [[ -d "${OUT}" ]]; then
  echo "Done."
  echo "Generated: ${WORKDIR}/${OUT}"
else
  echo "Expected output not found: ${WORKDIR}/${OUT}" >&2
  exit 2
fi


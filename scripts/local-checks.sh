#!/usr/bin/env bash
# Same gates as CI, run locally through Docker so nothing extra needs installing.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

terraform fmt -check -recursive -diff
./scripts/validate-all.sh

docker run --rm -v "$PWD":/src -w /src --entrypoint sh ghcr.io/terraform-linters/tflint:v0.59.1 \
  -c 'tflint --init && tflint --recursive --config /src/.tflint.hcl'

docker run --rm -v "$PWD":/src -w /src aquasec/trivy:0.76.2 config --config trivy.yaml --exit-code 1 .

#!/usr/bin/env bash
# Apaga a stack e os artefatos (no Floci nao custa nada, mas e o habito certo).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/comum.sh
conferir_conta
BUCKET=$(saida BucketEntrada 2>/dev/null || true)
[ -n "$BUCKET" ] && [ "$BUCKET" != "None" ] && aws s3 rm "s3://$BUCKET" --recursive >/dev/null || true
aws cloudformation delete-stack --stack-name "$STACK"
aws s3 rm s3://artefatos-lambda --recursive >/dev/null 2>&1 || true
aws s3 rb s3://artefatos-lambda >/dev/null 2>&1 || true
echo "Stack $STACK apagada."

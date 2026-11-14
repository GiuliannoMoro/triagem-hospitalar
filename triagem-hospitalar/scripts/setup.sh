#!/usr/bin/env bash
# Sobe tudo do zero: containers, modelo e a stack CloudFormation.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/comum.sh

echo "== 1/4 Containers =="
docker compose up -d
echo "Aguardando o Floci responder..."
for _ in $(seq 1 30); do aws sts get-caller-identity >/dev/null 2>&1 && break; sleep 2; done
conferir_conta

echo "== 2/4 Modelo llama3.2 (so baixa na primeira vez) =="
docker compose exec -T ollama ollama pull llama3.2

echo "== 3/4 Empacotando a Lambda =="
mkdir -p build
rm -f build/funcao.zip
(cd src && python3 -m zipfile -c ../build/funcao.zip handler.py)
CHAVE="funcao-$(date +%s).zip"
aws s3 mb s3://artefatos-lambda >/dev/null 2>&1 || true
aws s3 cp build/funcao.zip "s3://artefatos-lambda/$CHAVE" >/dev/null
echo "Codigo enviado: s3://artefatos-lambda/$CHAVE"

echo "== 4/4 Deploy da stack $STACK =="
aws cloudformation deploy --template-file infra/template.yaml --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM --parameter-overrides CodeKey="$CHAVE"
aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs" --output table
echo
echo "Pronto. Agora rode: ./scripts/testar.sh"

#!/usr/bin/env bash
# Envia os chamados de exemplo, espera a triagem e mostra resultado, custo e alertas.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/comum.sh
conferir_conta

BUCKET=$(saida BucketEntrada)
FILA=$(saida FilaAlertasUrl)
FILA=${FILA/floci:4566/localhost:4566}   # a URL vem com o hostname interno do container

enviar() { # enviar arquivo
  local nome inicio
  nome=$(basename "$1")
  inicio=$(date +%s)
  aws s3 cp "$1" "s3://$BUCKET/$nome" >/dev/null
  for _ in $(seq 1 60); do
    if aws dynamodb get-item --table-name chamados --key "{\"id\":{\"S\":\"$nome\"}}" \
         --query Item.id.S --output text 2>/dev/null | grep -q "$nome"; then
      echo "  $nome triado em $(( $(date +%s) - inicio )) s"; return; fi
    sleep 5
  done
  echo "  $nome: sem resultado apos 5 minutos (veja: aws logs tail /aws/lambda/triagem-chamados)"
}

echo "== Enviando chamados =="
for f in exemplos/*.txt; do enviar "$f"; done

echo
echo "== Resultado da triagem =="
aws dynamodb scan --table-name chamados \
  --query "Items[].[id.S, prioridade.S, prioridade_modelo.S, revisao_humana.BOOL, motivo.S, equipamento.S]" \
  --output table

echo "== Texto que foi para o modelo (ja anonimizado) =="
aws dynamodb scan --table-name chamados --query "Items[].[id.S, texto_anonimizado.S]" --output text

echo
echo "== Custo projetado (Claude Haiku 4.5 no Bedrock: US\$1/M entrada, US\$5/M saida) =="
aws dynamodb scan --table-name chamados --query "Items[?tokens_in.N!='0'].[tokens_in.N, tokens_out.N, latencia_ms.N]" --output text |
  awk '{i+=$1; o+=$2; l+=$3; n++} END {
    if (n==0) {print "  sem dados"; exit}
    c=(i/n)*1e-6 + (o/n)*5e-6
    printf "  media por chamado: %.0f tokens entrada, %.0f saida, %.1f s no modelo local\n", i/n, o/n, l/n/1000
    printf "  custo por chamado: US$ %.6f\n", c
    printf "  200 chamados/dia (6.000/mes): US$ %.2f por mes\n", c*6000 }'

echo
echo "== Alertas que chegaram na fila (prioridade alta) =="
aws sqs receive-message --queue-url "$FILA" --max-number-of-messages 10 --wait-time-seconds 2 \
  --query "Messages[].Body" --output text | python3 -c '
import json, sys
for linha in sys.stdin.read().split("\t"):
    linha = linha.strip()
    if not linha: continue
    try:
        corpo = json.loads(linha); msg = json.loads(corpo.get("Message", "{}"))
        print("  -", corpo.get("Subject", ""), "| revisao humana:", msg.get("revisao_humana"))
    except Exception:
        print("  -", linha[:150])
'

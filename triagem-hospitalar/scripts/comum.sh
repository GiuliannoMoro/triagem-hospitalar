# Configuracao compartilhada pelos scripts. Licao da Etapa 2: o endpoint fica
# explicito aqui, em vez de depender so do perfil, e a conta e conferida antes de tudo.
export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_PAGER=""
unset AWS_PROFILE
STACK="triagem-hospitalar"

conferir_conta() {
  local conta
  conta=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "?")
  if [ "$conta" != "000000000000" ]; then
    echo "PARE: a conta e '$conta', nao a do Floci (000000000000). Nada foi feito." >&2
    exit 1
  fi
  echo "Conta conferida: 000000000000 (Floci)"
}

saida() { # saida NomeDoOutput
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

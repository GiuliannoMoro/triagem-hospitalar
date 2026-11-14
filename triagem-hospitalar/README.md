# Triagem de chamados de manutenção hospitalar com GenAI e LGPD

**Projeto integrador — GenAI na Automação de Serviços AWS (AG822)**
**Nome:** Giulianno Lucas Moro
**Tema:** Saúde — classificação de chamados de manutenção de equipamentos hospitalares, com anonimização obrigatória antes da chamada ao modelo.

Um técnico ou enfermeiro abre um chamado em texto ("o ventilador do leito 4 da UTI parou"). O sistema tira os dados pessoais do texto, pede a um modelo de IA um resumo e a prioridade, aplica uma regra fixa de segurança, grava o resultado e, se a prioridade for alta, avisa a equipe de manutenção na hora. Tudo roda localmente no **Floci + Ollama**, sem conta da AWS e sem custo.

## Papéis da IA no projeto

| Papel          | Onde aparece                                                                                                                                                                                                                                                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Componente** | Dentro da Lambda, o Bedrock (Converse API) gera o resumo, identifica o equipamento e sugere a prioridade de cada chamado.                                                                                                                                                                                                                   |
| **Assistente** | O Claude gerou o template CloudFormation, a Lambda, os scripts e os testes, e o grupo revisou cada parte. No VS Code, o Claude Code com os servidores MCP `aws-docs` e `aws-knowledge` é usado para operar e ajustar o projeto no Floci. Os erros encontrados e corrigidos estão em [docs/diario-de-prompts.md](docs/diario-de-prompts.md). |

## Arquitetura

```mermaid
flowchart LR
    U[Técnico / enfermeiro] -->|chamado .txt| S3[(S3<br/>chamados-entrada)]
    S3 -->|ObjectCreated| L[Lambda triagem-chamados]
    L -->|1. anonimiza CPF, nomes,<br/>prontuário, telefone| L
    L -->|2. texto anonimizado| B[Bedrock Runtime<br/>Floci → Ollama llama3.2]
    B -->|JSON: equipamento,<br/>resumo, prioridade| L
    L -->|3. regra fixa:<br/>UTI, ventilador, desfibrilador...| L
    L -->|4. resultado| D[(DynamoDB<br/>chamados)]
    L -->|5. se alta| T[SNS<br/>alertas-manutencao]
    T --> Q[SQS<br/>fila-manutencao]
    L -.->|logs estruturados| CW[CloudWatch Logs]
```

Versão em imagem para os slides: [docs/arquitetura.png](docs/arquitetura.png) (editável em [docs/arquitetura.svg](docs/arquitetura.svg)). Explicação passo a passo: [docs/arquitetura.md](docs/arquitetura.md).

## Como rodar (3 comandos)

**Pré-requisitos:** Docker (no Windows, Docker Desktop com integração WSL ligada), AWS CLI v2.13 ou mais nova e Python 3. Uns 8 GB de RAM livres para o Ollama.

```bash
./scripts/setup.sh     # sobe Floci + Ollama, baixa o modelo e faz o deploy da stack
./scripts/testar.sh    # envia 4 chamados de exemplo e mostra triagem, custo e alertas
./scripts/limpar.sh    # apaga a stack
```

Os scripts usam o endpoint `http://localhost:4566` de forma explícita e **param antes de fazer qualquer coisa** se a conta não for a `000000000000` do Floci.

**Validações extras:**

```bash
uvx cfn-lint infra/template.yaml                                      # lint do template
uv run --with boto3 python -m unittest discover -s tests -v           # 10 testes offline da Lambda
```

## O que a demonstração mostra

Resultado real no Floci (detalhes no [diário de prompts](docs/diario-de-prompts.md#6-execução-no-floci)): os 4 chamados saíram com a prioridade esperada, e no chamado-004 o modelo obedeceu a injeção e sugeriu baixa, mas a regra fixa corrigiu para alta.

![Resultado do testar.sh](docs/prints/testar.png)

| Chamado     | Situação                                                                     | Esperado                                                               |
| ----------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| chamado-001 | Bomba de infusão com erro, **com nome, CPF, prontuário e telefone** no texto | media, e nenhum dado pessoal chega ao modelo nem à tabela              |
| chamado-002 | Ventilador da UTI parou                                                      | alta, com alerta na fila                                               |
| chamado-003 | Lâmpada queimada na sala de espera                                           | baixa                                                                  |
| chamado-004 | Desfibrilador não liga **+ injeção de prompt** pedindo prioridade baixa      | alta mesmo que o modelo obedeça a injeção, marcado para revisão humana |

O `testar.sh` mostra a prioridade final, a prioridade que o modelo sugeriu, se a regra fixa precisou corrigir e o texto exatamente como foi enviado ao modelo.

## Segurança e LGPD

- **Anonimização antes do modelo:** CPF, nomes (depois de "paciente", "técnico responsável", "Dr." etc.), prontuário, telefone e e-mail viram `[CPF]`, `[NOME]`, `[PRONTUARIO]`... O texto original nunca vai para o Bedrock, para a tabela nem para os logs.
- **Menor privilégio:** a role da Lambda só pode ler objetos do bucket de entrada, chamar **um** modelo, gravar (`PutItem`) na tabela `chamados`, publicar no tópico de alertas e escrever no próprio grupo de log. A checagem de IAM do Floci fica ligada no `docker-compose.yml`.
- **Defesa contra injeção de prompt:** o chamado vai entre `<chamado>` e o prompt de sistema manda ignorar instruções dentro dele. Como modelos pequenos obedecem a injeção mesmo assim (vimos isso na Etapa 6), uma **regra fixa no código** força prioridade alta quando aparecem termos críticos (UTI, ventilador, desfibrilador, suporte à vida, centro cirúrgico, "parou", "não liga") e marca o chamado para revisão humana.
- **Falha segura:** se o modelo cair ou devolver algo que não é JSON, o chamado vira **alta + revisão humana**, nunca baixa.
- **Rastreabilidade:** cada triagem gera um log estruturado no CloudWatch Logs (sem o texto), com prioridade, motivo, tokens e latência.

## Custo e TI Verde

Custo calculado com o Claude Haiku 4.5 no Bedrock (US$ 1,00 por milhão de tokens de entrada e US$ 5,00 por milhão de saída), a partir dos tokens que o `testar.sh` mediu nos 4 chamados de exemplo: **206 de entrada e 40 de saída** em média.

- Por chamado: 206 × 0,000001 + 40 × 0,000005 = **US$ 0,000405**
- 200 chamados por dia (6.000 por mês): **cerca de US$ 2,43 por mês**, mais centavos de Lambda, S3, DynamoDB e SNS.
- No modelo local, cada chamado levou em média 9,9 s na CPU.

**Otimizações aplicadas:** `maxTokens` limitado a 200, `temperature` 0, prompt curto, tabela em modo sob demanda (sem capacidade parada) e nenhum servidor ligado o tempo todo. Uma EC2 com GPU (g4dn.xlarge, US$ 0,526/h) custaria uns US$ 384 por mês ligada 24 h, mais de 150 vezes o custo do Bedrock nesse volume, e gastaria energia parada. Para poucos chamados por dia, usar um modelo pequeno compartilhado na nuvem é mais barato e mais sustentável. O modelo local faz sentido se o hospital não puder enviar nem o texto anonimizado para fora da sua rede.

## O que mudaria na AWS real

- **Modelo:** trocar o parâmetro `ModelId` por um modelo habilitado na conta (por exemplo, o Claude Haiku 4.5), e ajustar o ARN na política.
- **Anonimização:** usar o **Amazon Comprehend Medical** (`DetectPHI`) em vez de expressões regulares, que não pegam todo nome ou formato de documento.
- **Endpoint:** tirar o `AWS_ENDPOINT_URL` dos scripts e usar um perfil com credenciais temporárias (SSO), nunca chaves fixas.
- **Antes do deploy:** `aws cloudformation validate-template` e change sets.
- **Proteção dos dados:** criptografia com KMS no bucket, na tabela e no tópico; ciclo de vida para apagar os chamados brutos do S3 depois de alguns dias; região em São Paulo (`sa-east-1`) se o modelo estiver disponível lá.
- **Operação:** fila de mensagens com falha (DLQ) para a Lambda, alarme no CloudWatch para erros, assinatura de e-mail ou SMS no tópico e CloudTrail ligado para auditoria.
- **Custo:** cada recurso passa a custar até ser apagado; o nome do bucket já inclui o número da conta para ser único no mundo.

## Limitações conhecidas

- A anonimização por regex cobre os formatos testados, mas pode deixar passar nomes escritos de outro jeito. Por isso o texto bruto fica só no bucket de entrada.
- O llama3.2 local é um piso de qualidade: classifica pior e mais devagar (8 a 15 s por chamado na CPU) que um modelo do Bedrock.
- No Floci, o AgentCore e parte do Bedrock são emulados de forma simplificada; ver a documentação de serviços do Floci.

## Estrutura do repositório

```
docker-compose.yml        Floci (com IAM enforcement) + Ollama
infra/template.yaml       Toda a infraestrutura em CloudFormation
src/handler.py            Lambda: anonimiza, chama o Bedrock, aplica a regra fixa, grava e avisa
tests/test_handler.py     Testes offline (anonimização, regra, injeção, falha segura)
scripts/                  setup.sh, testar.sh, limpar.sh e comum.sh
exemplos/                 4 chamados de teste
docs/                     arquitetura, diário de prompts e roteiro da apresentação
```

# fcg-payments-service (PaymentsAPI + Worker)

Simula o pagamento dos pedidos. O worker consome `PedidoRealizadoEvento`, decide aprovado ou
rejeitado, grava o pagamento e publica `PagamentoProcessadoEvento`. A API só consulta.

## Endpoints

| Endpoint | Acesso | O que faz |
|---|---|---|
| `GET /pagamentos/{orderId}` | autenticado | status do pagamento do pedido (`Aprovado`/`Rejeitado`, motivo, valor) |
| `GET /health` · `GET /health/live` | anônimo | health checks |

## Regra de aprovação (determinística, para a demo)

| Preço | Status | Motivo |
|---|---|---|
| ≤ 0 | Rejeitado | `Valor inválido` |
| > 100 | Rejeitado | `Limite de crédito excedido` |
| demais | Aprovado | — |

Com o seed do catalog: Hades (R$ 49,90) é aprovado; Cyberpunk 2077 (R$ 149,90) é rejeitado.

## Eventos

| Evento | Papel | Fila | O que acontece |
|---|---|---|---|
| `PedidoRealizadoEvento` | consome (worker) | `payments-pedido-realizado` | aplica a regra, grava `Pagamento`, publica o resultado; pedido já processado é ignorado (idempotência por `PedidoId`) |
| `PagamentoProcessadoEvento` | publica (worker) | — | consumido pelo catalog e pelas notificações |

Falha no consumer: 3 novas tentativas (5 s, 10 s, 30 s). Contratos:
[`fcg-integration-events`](https://github.com/FIAP-POS-TECH-TEAM-10/fcg-integration-events).

## Dados

SQLite com a tabela `Pagamentos` (`PedidoId` único). API e worker usam o mesmo arquivo.

## Variáveis de ambiente

| Variável | Obrigatória | O que é |
|---|---|---|
| `JWT__KEY` · `JWT__ISSUER` | sim (API) | validação do JWT (mesma chave do users) |
| `ConnectionStrings__DefaultConnection` | não (`Data Source=fcgames-payments.db`) | SQLite |
| `Messaging__Provider` | não | `Sqs` = SQS/SNS (AWS); vazio + `RabbitMQ__Host` = RabbitMQ; nenhum = em memória |
| `AWS__Region` | não | região do SQS/SNS |
| `RabbitMQ__Host` · `RabbitMQ__Username` · `RabbitMQ__Password` | com RabbitMQ | broker local |

Segredos não ficam no repositório: localmente vêm do `.env` do
[`fcg-orchestration`](https://github.com/FIAP-POS-TECH-TEAM-10/fcg-orchestration); no EKS, do Secret `fcg-jwt`.

## Rodar local

Jeito recomendado: `docker compose up` no `fcg-orchestration`. Só este serviço (precisa de RabbitMQ
ou das variáveis acima):

```bash
export NUGET_AUTH_TOKEN=$(gh auth token)   # pacote FCGames.IntegrationEvents (read:packages)
dotnet run --project app/src/Fiap.FCGames.Payments.Api       # http://localhost:5003
dotnet run --project app/src/Fiap.FCGames.Payments.Worker    # outro terminal
```

Imagens: `docker build --secret id=GITHUB_TOKEN,env=NUGET_AUTH_TOKEN -t fcg-payments-service .`
(API) e `-f Dockerfile.worker` (worker).

## Na AWS

- Pod `payments-api` no EKS `fcg-eks` (namespace `fcgames`) com 2 containers: `api` e `worker`
  (mesmo SQLite em disco efêmero). ALB em `/pagamentos`.
- Imagens no ECR `fcg-payments-service` (`:<sha7>`/`:latest` e `:worker-<sha7>`/`:worker-latest`).
- SQS/SNS pela role `fcg-eks-payments-api` (Pod Identity). Ainda não expõe `/metrics`.
- Manifests: `fcg-orchestration/k8s/eks`.

## CI/CD

`.github/workflows/ci-cd.yml`: PR → build, testes, imagens e Trivy. Merge na `main` → também push no
ECR e rolling update do pod; com o cluster desligado o deploy é pulado e as imagens entram no próximo
"Ligar". Ainda não há projeto de testes.

Para Kind/Docker Desktop local, ver [`k8s/README.md`](k8s/README.md).

# fcg-payments-api


Microsserviço de pagamentos do projeto FCGames — Tech Challenge FIAP Fase 2.

Responsável por processar pedidos de compra, simular aprovação/rejeição e notificar os demais serviços via RabbitMQ.

---

## Arquitetura

```
Fiap.FCGames.Payments.Api      — HTTP :5003  (consulta de pagamentos + health)
Fiap.FCGames.Payments.Worker   — Worker Service (consumer RabbitMQ)
Fiap.FCGames.Payments.Domain   — Entidade Pagamento + enum StatusPagamento
Fiap.FCGames.Payments.Infra    — EF Core, PagamentoRepository, migrations
Fiap.FCGames.Payments.Application — Query BuscarPagamento (CQRS/MediatR)
Fiap.FCGames.Payments.CrossCutting — JWT, Swagger, Serilog, MassTransit extensions
```

### Fluxo de mensagens

```
CatalogAPI
  └── publica PedidoRealizadoEvento
        └── [fila: payments-pedido-realizado]
              └── Payments.Worker consome
                    ├── verifica idempotência por PedidoId
                    ├── aplica regra de aprovação
                    ├── persiste Pagamento no payments-db
                    └── publica PagamentoProcessadoEvento
                          ├── CatalogAPI: atualiza Pedido + Biblioteca
                          └── NotificationsAPI: log de confirmação/rejeição
```

---

## Endpoints

### `GET /pagamentos/{orderId}` — [Authorize]

Consulta o status de um pagamento pelo ID do pedido.

**Response 200:**
```json
{
  "orderId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "valor": 49.90,
  "status": "Aprovado",
  "motivo": null,
  "processadoEm": "2026-06-21T10:00:05Z"
}
```

**Response 404:** pagamento não encontrado para o `orderId` informado.

---

### `GET /health` — sem auth

Liveness/readiness probe usado pelo orquestrador (ECS na AWS / Kubernetes localmente).

**Response 200:**
```json
{ "status": "Healthy" }
```

---

## Regra de Aprovação

A simulação é determinística para facilitar a demonstração em vídeo:

| Condição | Status | Motivo |
|----------|--------|--------|
| Preço ≤ 0 | Rejeitado | `"Valor inválido"` |
| Preço > R$ 100 | Rejeitado | `"Limite de crédito excedido"` |
| Demais | Aprovado | `null` |

**Jogos de exemplo para a demo:**
- Hades II — R$ 49,90 → **Aprovado**
- Cyberpunk 2077 — R$ 149,90 → **Rejeitado**

---

## Banco de Dados

**payments-db** (SQLite em dev / PostgreSQL em prod):

```sql
CREATE TABLE Pagamentos (
    Id           TEXT PRIMARY KEY,
    PedidoId     TEXT NOT NULL UNIQUE,  -- chave de idempotência
    UsuarioId    TEXT NOT NULL,
    JogoId       TEXT NOT NULL,
    Valor        REAL NOT NULL,
    Status       INTEGER NOT NULL,      -- 0=Pendente, 1=Aprovado, 2=Rejeitado
    Motivo       TEXT,
    ProcessadoEm TEXT NOT NULL
);
```

A migration é aplicada automaticamente no startup de ambos os projetos (API e Worker).

---

## Eventos

### Consome

**`PedidoRealizadoEvento`** — publicado pelo CatalogAPI
```csharp
record PedidoRealizadoEvento(
    Guid PedidoId, Guid UsuarioId, Guid JogoId, string NomeJogo,
    decimal Preco, DateTime RealizadoEmUtc, Guid CorrelationId);
```

Fila: `payments-pedido-realizado`
Retry: 3 tentativas — 5s / 10s / 30s

### Publica

**`PagamentoProcessadoEvento`** — consumido por CatalogAPI e NotificationsAPI
```csharp
record PagamentoProcessadoEvento(
    Guid PedidoId, Guid UsuarioId, Guid JogoId, string NomeJogo,
    decimal Preco, string Status, string? Motivo,
    DateTime ProcessadoEmUtc, Guid CorrelationId);
// Status: "Aprovado" | "Rejeitado"
```

---

## Variáveis de Ambiente

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `JWT__KEY` | Chave de assinatura JWT (mínimo 32 chars) | `MinhaChaveSegredo...` |
| `JWT__ISSUER` | Issuer validado no token | `AppFiapFcGames` |
| `ConnectionStrings__DefaultConnection` | Connection string do banco | `Data Source=fcgames-payments.db` |
| `RabbitMQ__Host` | Host do RabbitMQ (usado se `Messaging__Provider` não for `Sqs`) | `rabbitmq` |
| `RabbitMQ__Username` | Usuário RabbitMQ | `guest` |
| `RabbitMQ__Password` | Senha RabbitMQ | `guest` |
| `Messaging__Provider` | `Sqs` usa Amazon SQS/SNS (deploy AWS). Vazio + `RabbitMQ__Host` → RabbitMQ. Nenhum dos dois → in-memory | `Sqs` |
| `AWS__Region` | Região usada pelo transporte SQS/SNS quando `Messaging__Provider=Sqs` | `sa-east-1` |

> **Segredos nunca devem estar no `appsettings.json` de produção.** Use env vars ou Kubernetes secrets.

> **Mensageria:** o transporte é escolhido em runtime (`AddMassTransitMessaging` na Api, mesmo padrão
> inline no `Worker/Program.cs`) — o consumer, o retry policy e o código de aplicação não mudam entre
> RabbitMQ e SQS. No ECS/AWS, o SDK usa a **Task Role** da task definition
> (`fcg-payments-service-ecs-task-role`) pra autenticar no SQS/SNS — nenhuma credencial no código.

---

## Rodando Localmente

### Pré-requisitos

- .NET 10 SDK
- RabbitMQ rodando em `localhost:5672` (ou via Docker)
- `NUGET_AUTH_TOKEN` com scope `read:packages` (para restaurar `FCGames.IntegrationEvents`)

### 1. Configurar NUGET_AUTH_TOKEN

```bash
# PowerShell
$env:NUGET_AUTH_TOKEN = "ghp_..."

# bash
export NUGET_AUTH_TOKEN=ghp_...
```

### 2. Restaurar e rodar a API

```bash
cd app/src
dotnet restore Fiap.FCGames.Payments.Api.slnx
dotnet run --project Fiap.FCGames.Payments.Api
# http://localhost:5003
```

### 3. Rodar o Worker (terminal separado)

```bash
cd app/src
dotnet run --project Fiap.FCGames.Payments.Worker
```

### RabbitMQ via Docker (rápido)

```bash
docker run -d --name rabbitmq \
  -p 5672:5672 -p 15672:15672 \
  rabbitmq:3-management
# Management UI: http://localhost:15672 (guest/guest)
```

---

## Estrutura de Pastas

```
fcg-payments-api/
├── nuget.config                          # feed GitHub Packages (FCGames.IntegrationEvents)
├── app/src/
│   ├── Fiap.FCGames.Payments.Api/
│   │   ├── Controllers/PagamentosController.cs
│   │   ├── Program.cs
│   │   └── appsettings.Development.json
│   ├── Fiap.FCGames.Payments.Worker/
│   │   ├── Consumers/PedidoRealizadoEventoConsumer.cs
│   │   ├── Program.cs
│   │   └── appsettings.json
│   ├── Fiap.FCGames.Payments.Application/
│   │   └── Queries/BuscarPagamento/
│   ├── Fiap.FCGames.Payments.Domain/
│   │   └── Aggregates/AggregatePagamento/Pagamento.cs
│   ├── Fiap.FCGames.Payments.Infra/
│   │   ├── DataProvider/Contexto/FcGamesContexto.cs
│   │   ├── DataProvider/Repositories/PagamentoRepository.cs
│   │   └── Migrations/
│   └── Fiap.FCGames.Payments.CrossCutting/
│       └── Extensions/
└── docs/
```

---

## Checklist de Entrega

- [x] Domínio: `Pagamento` + `StatusPagamento`
- [x] EF Core migration (`Pagamentos` com índice único em `PedidoId`)
- [x] `GET /pagamentos/{orderId}` [Authorize]
- [x] `GET /health`
- [x] Consumer `PedidoRealizadoEvento` com regra determinística
- [x] Publisher `PagamentoProcessadoEvento`
- [x] Idempotência por `PedidoId`
- [x] Retry 3x (5s / 10s / 30s)
- [x] Fila: `payments-pedido-realizado`
- [x] Projeto Worker separado
- [x] `nuget.config` (GitHub Packages)
- [ ] Dockerfile multi-stage (API + Worker)
- [ ] Manifests Kubernetes (`/k8s/`)

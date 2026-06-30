# Payments API - Kubernetes Deployment

Este diretório contém os manifestos Kubernetes para deploy do microsserviço Payments API e seu Worker.

## Recursos

- **Deployment API**: Define os Pods da API
- **Deployment Worker**: Define os Pods do Worker (consumer)
- **Service**: Expõe a API dentro do cluster
- **ConfigMap**: Configurações não sensíveis
- **Secret**: Credenciais e dados sensíveis
- **PersistentVolumeClaim**: Volume compartilhado entre API e Worker (ReadWriteMany)

## Deploy

### 1. Build das Imagens Docker

```bash
# API
docker build -t fcg-payments-api:latest -f Dockerfile .

# Worker
docker build -t fcg-payments-worker:latest -f Dockerfile.worker .
```

### 2. Aplicar Manifestos

```bash
kubectl apply -f k8s/
```

### 3. Verificar Status

```bash
# API
kubectl get pods -n fcgames -l app=payments-api
kubectl logs -n fcgames -l app=payments-api -f

# Worker
kubectl get pods -n fcgames -l app=payments-worker
kubectl logs -n fcgames -l app=payments-worker -f
```

## Configurações

### ConfigMap (configmap.yaml)
- `jwt-issuer`: Issuer do token JWT
- `rabbitmq-host`: Host do RabbitMQ
- `aspnetcore-urls`: URLs que a API escuta

### Secret (secret.yaml)
- `jwt-key`: Chave secreta para assinar tokens JWT
- `db-connection`: String de conexão do banco de dados
- `rabbitmq-username`: Usuário do RabbitMQ
- `rabbitmq-password`: Senha do RabbitMQ

**IMPORTANTE**: Altere os valores dos Secrets em produção!

## Acesso

### Port Forward para acesso local

```bash
kubectl port-forward -n fcgames svc/payments-api 5003:80
```

Acesse: http://localhost:5003

## Endpoints

- `GET /api/pagamentos` - Listar pagamentos
- `GET /api/pagamentos/{id}` - Buscar pagamento por ID
- `GET /health` - Health check

## Dependências

- RabbitMQ (deve estar rodando no namespace fcgames)

## Eventos Consumidos (Worker)

- **OrderPlacedEvent**: Consumido para processar pagamento

## Eventos Publicados (Worker)

- **PaymentProcessedEvent**: Publicado após processar pagamento (Approved/Rejected)

## Nota sobre o Volume

O PVC usa `ReadWriteMany` para permitir que API e Worker compartilhem o mesmo banco SQLite. Em produção, considere usar um banco de dados externo.

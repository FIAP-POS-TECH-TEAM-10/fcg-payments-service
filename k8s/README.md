# payments em Kubernetes local (Kind / Docker Desktop)

Manifests só para cluster local (API e worker em deployments separados, volume compartilhado).
Na AWS o deploy usa `fcg-orchestration/k8s/eks` (API e worker no mesmo pod).

1. Crie o Secret real (o `secret.yaml` daqui é só modelo, com `REPLACE_ME`):

```bash
kubectl create secret generic payments-api-secret -n fcgames \
  --from-literal=jwt-key="$JWT__KEY" \
  --from-literal=db-connection="Data Source=/data/payments.db" \
  --from-literal=rabbitmq-username="$RABBITMQ__USERNAME" \
  --from-literal=rabbitmq-password="$RABBITMQ__PASSWORD"
```

2. Aplique os demais manifests (não use `kubectl apply -f k8s/`: aplicaria o modelo por cima do Secret):

```bash
kubectl apply -f k8s/configmap.yaml -f k8s/deployment-api.yaml -f k8s/deployment-worker.yaml -f k8s/pvc.yaml -f k8s/service.yaml
```

3. Teste:

```bash
kubectl get pods -n fcgames -l 'app in (payments-api,payments-worker)'
kubectl port-forward -n fcgames svc/payments-api 5003:80    # http://localhost:5003/health
```

Precisa do RabbitMQ no namespace `fcgames` (manifests em `fcg-orchestration/k8s`).

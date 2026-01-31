# Infrastructure

Shared Kubernetes infrastructure for the Polaris ecosystem.

## Overview

This repository contains Kustomize bases for shared infrastructure components used across:
- [polaris](https://github.com/josebiro/polaris) - AI-powered reliability risk analysis platform
- [incident_pipeline](https://github.com/josebiro/incident_pipeline) - Incident data processing pipeline
- [incident_crawler](https://github.com/josebiro/incident_crawler) - Public incident report collector

## Components

### Base Resources

| Component | Description |
|-----------|-------------|
| `postgres-paradedb` | PostgreSQL 17 with ParadeDB extensions (pg_search BM25, pgvector) |
| `redis` | Redis for caching and pub/sub |

### Usage

Reference these bases in your application's Kustomization:

```yaml
# your-app/k8s/overlays/local/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # Shared infrastructure (pinned version)
  - github.com/josebiro/infrastructure//base/postgres-paradedb?ref=v1.0.0
  - github.com/josebiro/infrastructure//base/redis?ref=v1.0.0
  # Your app resources
  - ../../base

# Override namespace if needed
namespace: my-app
```

### Overlays

| Overlay | Description |
|---------|-------------|
| `local` | Local development (minikube, Docker Desktop, kind) |
| `dev` | Development environment |
| `prod` | Production environment |

## Structure

```
infrastructure/
├── base/
│   ├── postgres-paradedb/     # ParadeDB-enabled PostgreSQL
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   └── kustomization.yaml
│   └── redis/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── kustomization.yaml
├── overlays/
│   ├── local/
│   ├── dev/
│   └── prod/
└── components/                # Optional Kustomize components
```

## Local Development

To deploy locally with all infrastructure:

```bash
# Using kustomize
kubectl apply -k overlays/local

# Or with kubectl directly
kustomize build overlays/local | kubectl apply -f -
```

## Version Pinning

Always pin to a specific version in production:

```yaml
resources:
  - github.com/josebiro/infrastructure//base/postgres-paradedb?ref=v1.0.0
```

For development, you can use `main` branch:

```yaml
resources:
  - github.com/josebiro/infrastructure//base/postgres-paradedb?ref=main
```

# ClinicFlow GitOps Repository (Helm + Argo CD)

This repository contains the **GitOps source of truth** for deploying **ClinicFlow** into **Dev / Staging / Prod** Kubernetes clusters using:

* **Helm** (packaging + configuration)
* **Argo CD** (continuous delivery / sync)
* **Jenkins** (build + push images + update GitOps values)
* **NGINX Ingress + cert-manager** (single HTTPS entrypoint per environment)
* **nip.io** (DNS-free hostnames)

ClinicFlow is deployed as a **microservices stack**:

* `identity` (NestJS)
* `scheduling` (NestJS)
* `profiles` (NestJS)
* `notifications` (NestJS)
* `web` (Next.js)

…and **4 Postgres instances** (one per service DB).

---

## Architecture Summary

### Environments

ClinicFlow runs in 3 separate clusters:

* **Dev:** 1 master + 2 workers
* **Staging:** 3 masters + 3 workers + 2 LBs + VIP
* **Prod:** 3 masters + 4 workers + 2 LBs + VIP

### Cluster add-ons already configured

* MetalLB
* NGINX Ingress Controller
* cert-manager
* metrics-server
* Kubernetes Dashboard

### Routing model (single host per environment)

All traffic enters via **one hostname** per environment and is routed by path:

* `/` → `web`
* `/identity` → `identity`
* `/scheduling` → `scheduling`
* `/profiles` → `profiles`
* `/notifications` → `notifications` *(optional exposure)*

This eliminates CORS issues because the UI calls APIs using **relative paths**.

---

## Storage Classes

Each environment uses its own StorageClass for persistent volumes:

* **Dev:** `nfs-dev`
* **Staging:** `nfs-staging`
* **Prod:** `nfs-prod`

---

## Container Images

Images are built and pushed to DockerHub:

* `docker.io/bludivehub/clinicflow-identity`
* `docker.io/bludivehub/clinicflow-scheduling`
* `docker.io/bludivehub/clinicflow-profiles`
* `docker.io/bludivehub/clinicflow-notifications`
* `docker.io/bludivehub/clinicflow-web`

### Tagging strategy

We deploy immutable tags using Git SHA:

* `sha-<shortsha>`

Optional convenience tags (not used for GitOps deployments):

* `dev-latest`, `staging-latest`, `prod-latest`

---

## Repo Structure

```
clinicflow-gitops/
  helm/
    clinicflow/                 # Helm umbrella chart
      Chart.yaml
      values.yaml               # Shared defaults
      templates/                # Common templates (ingress, helpers, etc.)
      charts/                   # Optional local subcharts

  environments/
    dev/values.yaml
    staging/values.yaml
    prod/values.yaml

  argocd/
    dev-app.yaml
    staging-app.yaml
    prod-app.yaml
```

### What lives where?

* `helm/clinicflow`: The Helm chart (templates, defaults)
* `environments/*/values.yaml`: Environment-specific overrides (storage class, hostnames, replicas, resource sizes)
* `argocd/*.yaml`: Argo CD Application manifests (one per environment/cluster)

---

## Postgres Strategy (4 DBs)

Each service has its own Postgres instance:

* `identity-db`
* `scheduling-db`
* `profiles-db`
* `notifications-db`

Each DB has:

* StatefulSet
* PVC (StorageClass depends on environment)
* Secret (username/password/dbname)

---

## Prisma Migrations Strategy (Jobs)

All Prisma migrations are executed as **Kubernetes Jobs per environment**:

* `identity-migrate`
* `scheduling-migrate`
* `profiles-migrate`
* `notifications-migrate`

These jobs:

* use the same service image tag as the release
* run `prisma migrate deploy`
* run **after Postgres is ready** and **before the services start**

### Ordering (recommended)

We enforce deployment order using **Argo CD sync waves** (preferred for GitOps):

* Wave 0: namespace + secrets
* Wave 1: postgres
* Wave 2: migration jobs
* Wave 3: application deployments
* Wave 4: ingress

---

## Ingress + nip.io Hostnames

Each environment uses a nip.io hostname based on the **Ingress Controller EXTERNAL-IP**.

Example pattern:

* `clinicflow-dev.<LB_IP>.nip.io`
* `clinicflow-staging.<LB_IP>.nip.io`
* `clinicflow-prod.<LB_IP>.nip.io`

> To get the external IP:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

TLS is provisioned via **cert-manager** (Let’s Encrypt or internal issuer depending on setup).

---

## Deployment Workflow (Jenkins → GitOps → Argo CD)

### 1) Jenkins builds & pushes images

Pipeline stages:

1. Checkout application repo (`clinicflow`)
2. Build 5 Docker images
3. Push images to DockerHub with tag `sha-<shortsha>`

### 2) Jenkins updates this GitOps repo

Jenkins updates `environments/<env>/values.yaml`:

* sets image tags to the new SHA

Then Jenkins commits and pushes changes.

### 3) Argo CD deploys automatically

Argo CD watches this repo and syncs the environment:

* Dev auto-sync on merge
* Staging can be auto-sync or manual
* Prod is typically manual sync or protected by approvals

---

## How to Deploy (per environment)

### Dev

1. Ensure Argo CD is installed in the Dev cluster
2. Apply `argocd/dev-app.yaml`
3. Argo will deploy Helm chart using `environments/dev/values.yaml`

### Staging

Same steps using `argocd/staging-app.yaml` and `environments/staging/values.yaml`

### Prod

Same steps using `argocd/prod-app.yaml` and `environments/prod/values.yaml`

---

## Smoke Test Checklist

After Argo deploy completes:

* Open the environment hostname (nip.io)
* Register/Login
* Book appointment (patient)
* View schedule (staff)
* Add visit note (staff)
* Confirm `/health` works for services (via ingress paths)

---

## Notes / Conventions

* No hardcoded localhost values in Kubernetes
* All sensitive data must live in Kubernetes Secrets (or ExternalSecrets/SealedSecrets)
* Do not deploy using `latest` tags
* Prefer immutable SHA tags for reliable rollbacks


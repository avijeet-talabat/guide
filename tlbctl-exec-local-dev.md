# tlbctl exec — Local Development Against QA / Production Cluster

Run any local service binary with full access to cluster services, env vars, and AWS credentials — no port-forwards, no mocks, no manual credential wrangling.

---

## Prerequisites

- `saml2aws` installed and configured with accounts `tlb-dev-2` (QA) and `tlb-prd-2` (prod)
- `kubectl` installed
- `make` and Go toolchain
- `tlbctl` built (see step 1)

---

## Step 1 — Build tlbctl

```bash
cd ~/Documents/talabat/tools/tlbctl
make build
```

Binary is written to `./bin/tlbctl`. You may want to alias it:

```bash
alias tlbctl=~/Documents/talabat/tools/tlbctl/bin/tlbctl
```

---

## Step 2 — Authenticate

Find the namespace your service lives in and login with the matching IAM role.

### QA (tlb-dev-2)

```bash
saml2aws login -a tlb-dev-2 --role arn:aws:iam::690772145391:role/<namespace> --force
```

Then update kubeconfig (first time only, or after cluster changes):

```bash
aws eks update-kubeconfig --region eu-west-2 --name talabat-qa-eks-az-2a-cluster --profile tlb-dev-2
aws eks update-kubeconfig --region eu-west-2 --name talabat-qa-eks-az-2b-cluster --profile tlb-dev-2
```

### Production (tlb-prd-2)

```bash
saml2aws login -a tlb-prd-2 --role arn:aws:iam::457710302499:role/<namespace> --force
```

Then update kubeconfig (first time only):

```bash
aws eks update-kubeconfig --region eu-west-2 --name talabat-prod-main-cluster --profile tlb-prd-2
aws eks update-kubeconfig --region eu-west-2 --name talabat-prod-failover-cluster --profile tlb-prd-2
```

If you are unsure of the role name, omit `--role` for an interactive picker.

**Re-login when you see:** `Error: resolve cluster identity: Unauthorized`

> **Production note:** `tlbctl exec` needs pod create permission. You may only have this in namespaces where your prod role has write access. Check with your team if you hit `pods is forbidden`.

---

## Step 3 — Find your service's namespace and workload

```bash
kubectl get rollout,deployment --all-namespaces | grep <service-name>
```

Note the namespace (e.g. `search-discovery`) and whether it is a `rollout` or `deployment`.

---

## Step 4 — Build your service binary

```bash
cd ~/Documents/talabat/<tribe>/<service-name>
make build        # or: go build -o <service-name> .
```

Make sure the binary exists locally before running `tlbctl exec`.

---

## Step 5 — Run with tlbctl exec

### Against QA

```bash
~/Documents/talabat/tools/tlbctl/bin/tlbctl exec \
  --context 2a \
  -n <namespace> \
  --as <rollout|deploy>/<service-name> \
  -- ./<binary-name>
```

### Against Production

```bash
~/Documents/talabat/tools/tlbctl/bin/tlbctl exec \
  --context talabat-prod-main-cluster \
  -n <namespace> \
  --as <rollout|deploy>/<service-name> \
  -- ./<binary-name>
```

Use `--context talabat-prod-failover-cluster` if targeting the failover cluster.

### Real examples

**personalisation-platform-service** (Rollout, search-discovery) — QA:
```bash
cd ~/Documents/talabat/clt/personalisation-platform-service
make build
~/Documents/talabat/tools/tlbctl/bin/tlbctl exec \
  --context 2a \
  -n search-discovery \
  --as rollout/personalisation-platform-service \
  -- ./personalisation-platform-service
```

**personalisation-platform-service** — Production:
```bash
saml2aws login -a tlb-prd-2 --role arn:aws:iam::457710302499:role/search-discovery --force
~/Documents/talabat/tools/tlbctl/bin/tlbctl exec \
  --context talabat-prod-main-cluster \
  -n search-discovery \
  --as rollout/personalisation-platform-service \
  -- ./personalisation-platform-service
```

**talabat-home-api-gateway** (Deployment, discovery) — QA:
```bash
cd ~/Documents/talabat/home/talabat-home-api-gateway
make build-lura-fast
~/Documents/talabat/tools/tlbctl/bin/tlbctl exec \
  --context 2a \
  -n discovery \
  --as deploy/talabat-home-api-gateway \
  --set LURA_CONFIG_FILE=./configs/lura.qa.json \
  --set APP_CONFIG_FILE=./configs/app_configs/app.qa.json \
  -- ./bin/talabat-home-api-gateway
```

---

## What tlbctl exec does

1. Spins up a lightweight proxy pod in the cluster impersonating your workload (same service account, same sidecar injection)
2. Port-forwards a SOCKS5 proxy + sidecar ports (OPA on `:8181`, etc.) to localhost
3. Reads the admitted pod spec (post-webhook) to capture all env vars — including ones injected by admission webhooks like IRSA (`AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`)
4. Reads the IRSA token from the pod and writes it to a local temp file — your service authenticates to AWS as the pod's IAM role
5. Re-signs your binary (macOS SIP escape) and runs it with `DYLD_INSERT_LIBRARIES` pointing at the intercept dylib
6. All `*.svc.cluster.local` DNS lookups are transparently routed through the SOCKS5 proxy into the cluster
7. Tears down the proxy pod on exit (Ctrl+C or normal exit)

---

## Flags

| Flag | Description |
|---|---|
| `--context` | Kube context hint, fuzzy-matched (e.g. `2a`, `qa`). Interactive picker if omitted. |
| `-n` | Namespace. Interactive picker if omitted. |
| `--as` | Workload to impersonate: `deploy/<name>` or `rollout/<name>`. Interactive picker if omitted. |
| `--set KEY=VALUE` | Override env var. Repeatable. Applied after pod env vars. |

---

## Overriding env vars

Use `--set` to override specific vars without changing anything else:

```bash
--set LOG_LEVEL=debug \
--set SOME_FEATURE_FLAG=true
```

The order of precedence (highest wins): `--set` > pod env vars > your local shell env.

---

## Troubleshooting

### `Unauthorized` on startup

Your AWS session has expired or you are using the wrong role. Re-login:

```bash
# QA
saml2aws login -a tlb-dev-2 --role arn:aws:iam::690772145391:role/<namespace> --force

# Production
saml2aws login -a tlb-prd-2 --role arn:aws:iam::457710302499:role/<namespace> --force
```

### `pods is forbidden: User "X" cannot create resource "pods" in namespace "Y"`

You are authenticated as role `X` but your service is in namespace `Y`. Login with the matching role (see Step 2).

### `no such file or directory` for your binary

You forgot to build the service first. Run `make build` (or the equivalent) before `tlbctl exec`.

### Config file not found (e.g. `/etc/lura/lura.qa.json`)

The pod's env has a config path that does not exist locally. Override it with `--set`:

```bash
--set LURA_CONFIG_FILE=./configs/lura.qa.json
```

### S3 / DynamoDB `ExpiredToken`

This was a known bug — fixed in the current `fix/exec-macos-injection` branch. The fix reads the IRSA web identity token from the proxy pod and makes it available locally. Make sure you are using the latest build.

If you still see it, your saml2aws session might have expired. Re-login and rebuild.

### 404 on curl to a Lura/KrakenD gateway

Lura routes use **path parameters**, not query params. Check `configs/lura.qa.json` for the actual route pattern:

```bash
python3 -c "
import json
d=json.load(open('configs/lura.qa.json'))
for e in d.get('endpoints', []):
    print(e['endpoint'])
"
```

---

## kubectl — Useful commands while tlbctl exec is running

### Watch the proxy pod spin up in real time

```bash
# QA
kubectl get pods -n <namespace> -w | grep tlbctl

# Production (always specify --context for prod)
kubectl get pods -n <namespace> -w \
  --context arn:aws:eks:eu-west-2:457710302499:cluster/talabat-prod-main-cluster \
  | grep tlbctl
```

Pod status progression:
```
Pending → Init:0/1 → PodInitializing → 0/3 Running → 3/3 Running (ready)
```

### Find your service's namespace and workload type

```bash
# QA
kubectl get rollout,deployment --all-namespaces | grep <service-name>

# Production
kubectl get rollout,deployment --all-namespaces \
  --context arn:aws:eks:eu-west-2:457710302499:cluster/talabat-prod-main-cluster \
  | grep <service-name>
```

### Inspect env vars in the live pod (what tlbctl will capture)

```bash
kubectl exec -n <namespace> deployment/<service-name> -- env | sort

# Filter for specific vars
kubectl exec -n <namespace> deployment/<service-name> -- env | grep -i aws
kubectl exec -n <namespace> deployment/<service-name> -- env | grep -i fwf
```

### Check OPA / sidecar health locally (while tlbctl exec is running)

```bash
# OPA health
curl -s localhost:8181/health

# OPA STS token (what your service uses to call downstream services)
curl -s localhost:8181/v1/token | python3 -m json.tool
```

### View logs of the actual pod in parallel

```bash
# Tail logs from the real service pod
kubectl logs -n <namespace> deployment/<service-name> -f --tail=50

# Tail from a specific container (e.g. if there are sidecars)
kubectl logs -n <namespace> deployment/<service-name> -c <service-name> -f
```

### Describe a pod (events, restarts, resource limits)

```bash
kubectl describe pod -n <namespace> <pod-name>
```

### Switch kubectl context

```bash
# List all contexts
kubectl config get-contexts

# Switch to QA 2a
kubectx arn:aws:eks:eu-west-2:690772145391:cluster/talabat-qa-eks-az-2a-cluster

# Switch to production
kubectx arn:aws:eks:eu-west-2:457710302499:cluster/talabat-prod-main-cluster

# Check current context
kubectx --current
```

### Clean up stale tlbctl proxy pods (if tlbctl crashed without cleanup)

```bash
kubectl get pods -n <namespace> | grep tlbctl-connect
kubectl delete pod -n <namespace> <pod-name>
```

---

## Namespace → IAM role mapping

### QA (account `690772145391`, saml2aws account `tlb-dev-2`)

| Namespace | IAM role |
|---|---|
| `discovery` | `arn:aws:iam::690772145391:role/discovery` |
| `search-discovery` | `arn:aws:iam::690772145391:role/search-discovery` |

### Production (account `457710302499`, saml2aws account `tlb-prd-2`)

| Namespace | IAM role |
|---|---|
| `discovery` | `arn:aws:iam::457710302499:role/discovery` |
| `search-discovery` | `arn:aws:iam::457710302499:role/search-discovery` |

Add more as you discover them.

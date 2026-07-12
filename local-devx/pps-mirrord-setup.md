# mirrord Setup for personalisation-platform-service

**Date:** 2026-07-12
**Service:** personalisation-platform-service
**Namespace:** search-discovery
**Cluster:** talabat-qa-eks-az-2a-cluster (eu-west-2, account 690772145391)

---

## 1. Prerequisites

- Install mirrord: `brew install metalbear-co/mirrord/mirrord`
- kubectl + optionally [kubectx/kubens](https://github.com/ahmetb/kubectx)
- **Cloudflare WARP must be DISABLED** (conflicts with VPN needed to reach private EKS endpoint)

## 2. AWS Authentication

You must explicitly assume the `search-discovery` IAM role. Using `saml2aws login -a tlb-dev-2` alone gives you the `discovery` role, which **does not** have `jobs.batch` permissions in the `search-discovery` namespace (mirrord needs this to deploy its agent).

```bash
saml2aws login -a tlb-dev-2 --role arn:aws:iam::690772145391:role/search-discovery --force
```

This authenticates via Okta and stores temporary AWS credentials for the `search-discovery` role. Credentials expire after ~12 hours.

## 3. kubectl Context & Namespace Setup

### Update kubeconfig

```bash
aws eks update-kubeconfig \
  --region eu-west-2 \
  --name talabat-qa-eks-az-2a-cluster \
  --profile tlb-dev-2
```

### Switch to the QA cluster context

```bash
kubectl config use-context arn:aws:eks:eu-west-2:690772145391:cluster/talabat-qa-eks-az-2a-cluster
# or with kubectx:
kubectx arn:aws:eks:eu-west-2:690772145391:cluster/talabat-qa-eks-az-2a-cluster
```

### Set default namespace to search-discovery

So you don't need `-n search-discovery` on every command:

```bash
kubectl config set-context --current --namespace=search-discovery
# or with kubens:
kubens search-discovery
```

### Verify you can see the deployment

```bash
kubectl get deployments
# Should show: personalisation-platform-service

# Verify you have the right permissions:
kubectl auth can-i create jobs.batch -n search-discovery
# Should print: yes
```

## 4. mirrord Configuration

Create `.mirrord/mirrord.json` in the project root (already gitignored):

```json
{
  "target": {
    "path": "deployment/personalisation-platform-service",
    "namespace": "search-discovery"
  },
  "feature": {
    "network": {
      "incoming": "mirror",
      "outgoing": true,
      "dns": true
    },
    "fs": "local",
    "env": {
      "exclude": "DH_SPEC_FILE"
    }
  },
  "agent": {
    "namespace": "search-discovery",
    "privileged": true
  },
  "kube_context": "arn:aws:eks:eu-west-2:690772145391:cluster/talabat-qa-eks-az-2a-cluster"
}
```

### Why `exclude: "DH_SPEC_FILE"` instead of `include + override`

`main.go` checks for `DH_SPEC_FILE` at startup:
- **Present** → reads GDP spec file at that path (used in deployed pods, path doesn't exist locally)
- **Absent** → falls back to `config/config.yml` (local Talabat config)

Excluding `DH_SPEC_FILE` makes the local process use the local config automatically. Note: you **cannot** use both `include` and `exclude` for env vars in mirrord — use one or the other.

## 5. How to Run

```bash
mirrord exec -f .mirrord/mirrord.json -- go run main.go
```

The service starts on port `8080`. mirrord duplicates incoming QA traffic to your local process — responses are discarded (mirror mode), so there's no impact on QA users.

## 6. How to Stop & Cleanup

1. `Ctrl+C` the mirrord process (agent pod auto-deletes)
2. Verify: `kubectl get pods -n search-discovery | grep mirrord`
3. Manual cleanup if needed: `kubectl delete pod -n search-discovery -l app=mirrord`

## 7. Key Findings & Known Limitations

### a) Config fallback ✅

Excluding `DH_SPEC_FILE` triggers the Talabat config path (`config/config.yml`). No additional env overrides needed.

### b) Agent namespace permissions ✅ RESOLVED

mirrord deploys its agent as a `jobs.batch` resource. The `discovery` IAM role (default for `tlb-dev-2`) does **not** have this permission in `search-discovery`. You must explicitly assume the `search-discovery` role:

```bash
# Wrong — gives discovery role, lacks jobs.batch in search-discovery:
saml2aws login -a tlb-dev-2

# Correct — explicitly assumes search-discovery role:
saml2aws login -a tlb-dev-2 --role arn:aws:iam::690772145391:role/search-discovery --force
```

### c) DNS resolution ✅

Set `agent.privileged: true` and `dns: true`. The cluster is hardened; without privileges the agent cannot perform DNS lookups for `*.svc.cluster.local` addresses.

### d) Filesystem mode ✅

Set `fs: "local"` — config files are loaded via env var fallback, no remote filesystem access needed.

### e) STS/OPA sidecar auth ❌ NOT RESOLVED

Downstream services requiring STS token validation return 401. mirrord outbound traffic bypasses pod sidecars (istio-proxy, OPA). **In mirror mode this doesn't matter — responses are discarded.**

### f) Steal mode with HTTP filter ❌ NOT WORKING with istio

istio intercepts traffic before mirrord can inspect HTTP headers. Filtered steal requires the mirrord Operator (paid Teams feature). **Use mirror mode only.**

## 8. Modes Summary

| Mode | Description | QA Impact | Status |
|------|-------------|-----------|--------|
| `mirror` | Duplicates traffic to local process. Responses discarded. | None | ✅ RECOMMENDED |
| `steal` | Intercepts all traffic. Local process responds to real users. | High risk | ⚠️ Use with caution |
| `steal` + `http_filter` | Filter by header to steal only specific requests. | Should be none | ❌ Broken with istio |

## 9. mirrord Config Field Reference

| Field | Value | Why |
|-------|-------|-----|
| `target.path` | `deployment/personalisation-platform-service` | Target the deployment (picks first pod) |
| `target.namespace` | `search-discovery` | Namespace where the service runs |
| `feature.network.incoming` | `"mirror"` | Safe mode — duplicates traffic |
| `feature.network.outgoing` | `true` | Route outbound calls through pod's network |
| `feature.network.dns` | `true` | Resolve `*.svc.cluster.local` via remote DNS |
| `feature.fs` | `"local"` | Use local filesystem |
| `feature.env.exclude` | `"DH_SPEC_FILE"` | Force fallback to local `config/config.yml` |
| `agent.namespace` | `"search-discovery"` | Namespace where search-discovery IAM role has batch/jobs permissions |
| `agent.privileged` | `true` | Required for DNS resolution on hardened clusters |
| `kube_context` | `arn:aws:eks:...` | Explicit QA cluster context |

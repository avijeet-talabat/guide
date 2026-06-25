# mirrord Setup for talabat-home-api-gateway

**Date:** 2026-06-24
**Service:** talabat-home-api-gateway
**Namespace:** discovery
**Cluster:** talabat-qa-eks-az-2a-cluster (eu-west-2, account 690772145391)

---

## 1. Prerequisites

- Install mirrord: `brew install metalbear-co/mirrord/mirrord`
- AWS credentials via saml2aws: `saml2aws login -a tlb-dev-2`
- kubectl context set to QA cluster:
  ```bash
  kubectl config use-context arn:aws:eks:eu-west-2:690772145391:cluster/talabat-qa-eks-az-2a-cluster
  ```
- **Cloudflare WARP must be DISABLED** (conflicts with VPN needed to reach private EKS endpoint)

## 2. Working mirrord Configuration

Create `.mirrord/mirrord.json` in the project root:

```json
{
  "target": {
    "path": "deployment/talabat-home-api-gateway",
    "namespace": "discovery"
  },
  "feature": {
    "network": {
      "incoming": "mirror",
      "outgoing": true,
      "dns": true
    },
    "fs": "local",
    "env": {
      "include": "*",
      "override": {
        "LURA_CONFIG_FILE": "configs/lura.qa.json",
        "APP_CONFIG_FILE": "configs/app_configs/app.qa.json",
        "RULE_ENGINE_CONFIG_FILE": "configs/rule_engine_config.qa.json"
      }
    }
  },
  "agent": {
    "namespace": "discovery",
    "privileged": true
  },
  "kube_context": "arn:aws:eks:eu-west-2:690772145391:cluster/talabat-qa-eks-az-2a-cluster"
}
```

## 3. How to Run

```bash
mirrord exec -f .mirrord/mirrord.json -- go run main.go
```

## 4. How to Stop & Cleanup

1. `Ctrl+C` the mirrord process (agent pod auto-deletes)
2. Verify: `kubectl get pods -n discovery | grep mirrord`
3. Manual cleanup if needed: `kubectl delete pod -n discovery -l app=mirrord`

## 5. Key Findings & Issues Resolved

### a) Config file paths ✅ RESOLVED

The QA pod mounts configs at `/etc/lura/` which doesn't exist locally. Override env vars to point to local config files in the `configs/` directory. Three env vars needed: `LURA_CONFIG_FILE`, `APP_CONFIG_FILE`, `RULE_ENGINE_CONFIG_FILE`.

### b) Agent namespace permissions ✅ RESOLVED

mirrord agent defaults to creating jobs in the `default` namespace. The `discovery` IAM role lacks permissions there. Set `agent.namespace` to `"discovery"`.

### c) DNS resolution ✅ RESOLVED

Cluster is hardened — agent can't perform DNS lookups without privileges. With `dns: false`, `*.svc.cluster.local` addresses can't resolve. Set `agent.privileged: true` and `dns: true`.

### d) Filesystem mode ✅ RESOLVED

`fs: "read"` (remote) caused issues with missing `/etc/lura/plugins/` directory. Set `fs: "local"` since we override config paths via env vars anyway.

### e) STS/OPA sidecar auth ❌ NOT RESOLVED

Downstream services requiring STS token validation return 401. mirrord outbound traffic bypasses pod sidecars (istio-proxy, OPA). This means STS token exchange doesn't happen for local outbound calls. Some downstream calls fail with 401 (e.g., cdp-core-api). **In mirror mode this doesn't matter — responses are discarded.**

### f) Steal mode with HTTP filter ❌ NOT WORKING with istio

Steal mode works but HTTP header filtering does NOT work with istio service mesh. istio intercepts traffic before mirrord can inspect HTTP headers. Result: ALL requests get stolen, not just filtered ones → causes 404s for QA users. Filtered steal requires the **mirrord Operator** (paid Teams feature). **Recommendation: Use mirror mode only.**

## 6. Modes Summary

| Mode | Description | QA Impact | Status |
|------|-------------|-----------|--------|
| `mirror` | Duplicates traffic to local process. Responses discarded. | None | ✅ RECOMMENDED |
| `steal` | Intercepts all traffic. Local process responds to real users. | High risk | ⚠️ Use with caution |
| `steal` + `http_filter` | Filter by header to steal only specific requests. | Should be none | ❌ Broken with istio |

## 7. Known Limitations

- **Downstream auth (STS/OPA)** doesn't work — outbound calls bypass sidecars
- **S3 vendor data** fails — AWS credentials from pod's IRSA don't transfer properly
- **Some downstream services** may be unhealthy in QA independently
- **Multi-pod impersonation** requires mirrord Operator (only first pod is targeted)

## 8. mirrord Config Field Reference

| Field | Value | Why |
|-------|-------|-----|
| `target.path` | `deployment/talabat-home-api-gateway` | Target the deployment (picks first pod) |
| `target.namespace` | `discovery` | Namespace where the service runs |
| `feature.network.incoming` | `"mirror"` | Safe mode — duplicates traffic |
| `feature.network.outgoing` | `true` | Route outbound calls through pod's network |
| `feature.network.dns` | `true` | Resolve `*.svc.cluster.local` via remote DNS |
| `feature.fs` | `"local"` | Use local filesystem |
| `feature.env.override` | `{...}` | Override config file paths to local equivalents |
| `agent.namespace` | `"discovery"` | Create agent pod where we have RBAC permissions |
| `agent.privileged` | `true` | Required for DNS resolution on hardened clusters |
| `kube_context` | `arn:aws:eks:...` | Explicit QA cluster context |

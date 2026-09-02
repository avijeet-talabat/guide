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

If your service loads Go plugins (`.so`), build those too — see [Lura gateways with
plugins](#lura-gateways-with-plugins).

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

**talabat-home-api-gateway** (Deployment, discovery)

This one is more involved than a plain service: it is a Lura/KrakenD gateway that
loads Go **plugins** (`.so`) and reads **three** config files, all of which point at
container paths that do not exist on your laptop. See
[Lura gateways with plugins](#lura-gateways-with-plugins) for the why.

QA:
```bash
cd ~/Documents/talabat/home/talabat-home-api-gateway

# 1. Build the binary AND the plugins (must be built together — see note below)
make build-lura-fast && make build-plugins-fast

# 2. Patch the plugin folder: /etc/lura/plugins/ -> ./bin/
python3 -c "
import json, pathlib
d = json.load(open('configs/lura.qa.json'))
d['plugin']['folder'] = './bin/'
pathlib.Path('/tmp/lura.qa.local.json').write_text(json.dumps(d))
"

# 3. Run
~/Documents/talabat/tools/tlbctl/bin/tlbctl exec \
  --context 2a \
  -n discovery \
  --as deploy/talabat-home-api-gateway \
  --set LURA_CONFIG_FILE=/tmp/lura.qa.local.json \
  --set APP_CONFIG_FILE=./configs/app_configs/app.qa.json \
  --set RULE_ENGINE_CONFIG_FILE=./configs/rule_engine_config.qa.json \
  -- ./bin/talabat-home-api-gateway
```

Production — identical, with `prod` configs and the prod context:
```bash
saml2aws login -a tlb-prd-2 --role arn:aws:iam::457710302499:role/discovery --force

cd ~/Documents/talabat/home/talabat-home-api-gateway
make build-lura-fast && make build-plugins-fast

python3 -c "
import json, pathlib
d = json.load(open('configs/lura.prod.json'))
d['plugin']['folder'] = './bin/'
pathlib.Path('/tmp/lura.prod.local.json').write_text(json.dumps(d))
"

~/Documents/talabat/tools/tlbctl/bin/tlbctl exec \
  --context talabat-prod-main-cluster \
  -n discovery \
  --as deploy/talabat-home-api-gateway \
  --set LURA_CONFIG_FILE=/tmp/lura.prod.local.json \
  --set APP_CONFIG_FILE=./configs/app_configs/app.prod.json \
  --set RULE_ENGINE_CONFIG_FILE=./configs/rule_engine_config.prod.json \
  -- ./bin/talabat-home-api-gateway
```

Only steps 2–3 need re-running between runs; rebuild only when you change code.

---

## Lura gateways with plugins

Three things bite you on a plugin-based gateway that do not apply to a normal service.

### 1. Plugins must be built with the binary, with matching flags

`make build-lura-fast` only builds the gateway. The `.so` files come from a separate
target:

```bash
make build-lura-fast && make build-plugins-fast
```

Go requires plugins and host binary to agree on Go version, dependency versions, **and
compiler flags**. The `-fast` targets both use `-ldflags="-s -w" -gcflags="all=-l"`, so
they pair correctly. Do **not** mix targets — `make build-lura` + `make
build-plugins-fast` will fail at `plugin.Open` with a "different version of package"
error.

### 2. `plugin.folder` is inside the JSON — `--set` cannot reach it

The config hardcodes the container path:

```json
"plugin": { "folder": "/etc/lura/plugins/", "pattern": ".so" }
```

That is a JSON field, not an env var, so there is no `--set` for it. Write a patched
copy to `/tmp` and point `LURA_CONFIG_FILE` at that (see the recipe above).

### 3. There are three config env vars, not two

`RULE_ENGINE_CONFIG_FILE` is easy to miss because it fails **later** than the other two
— the gateway starts, then errors when a rule is first evaluated. Override all three:

```bash
--set LURA_CONFIG_FILE=/tmp/lura.prod.local.json \
--set APP_CONFIG_FILE=./configs/app_configs/app.prod.json \
--set RULE_ENGINE_CONFIG_FILE=./configs/rule_engine_config.prod.json
```

### Verifying plugins actually loaded

Successful startup logs — if you see these, plugins are fine and any 404 is a
**routing** problem, not a loading one:

```
home aggregator loaded
template home aggregator loaded
Total client plugins loaded: 1
Total handler plugins loaded: 2
[PLUGIN: Server] Injecting plugin homeaggregator
[PLUGIN: Server] Injecting plugin templateaggregator
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

First confirm plugins loaded (see [Verifying plugins actually
loaded](#verifying-plugins-actually-loaded)). If they did, this is a routing mismatch,
not a plugin problem.

Dump the routes the running config actually registers:

```bash
python3 -c "
import json
d=json.load(open('configs/lura.prod.json'))
for e in d.get('endpoints', []):
    print(e.get('method','GET'), e['endpoint'])
"
```

**The `v1` vs `v2` trap.** On talabat-home-api-gateway the registered route is:

```
GET /home/v2/{country_code}/content/{device_source}/{lat}/{lon}/{area_id}/{country_id}/{address_id}
```

but the natural thing to curl is `/home/v1/ae/content?lat=...&lon=...`, which 404s. The
`homeaggregator` server plugin rewrites query params into **path segments** — appending
`device_source/lat/lon/area_id/country_id/address_id` onto whatever prefix you send. It
does not rewrite `v1` to `v2`. So send `v2` and let the plugin build the rest:

```bash
curl --location 'localhost:8080/home/v2/ae/content?countryId=4&area_id=1244&lat=25.218979394147638&lon=55.26518683611329' \
  --header 'X-Device-Source: 4' \
  --header 'X-Device-Version: 11.27.0' \
  --header 'X-Device-Framework: Flutter' \
  --header 'X-Device-Width: 400' \
  --header 'AppBrand: 1' \
  --header 'BrandType: 1' \
  --header 'Accept-Language: en-US' \
  --header 'X-Device-ID: 70C1DDFA-744D-4107-AC2A-BC030F3C21C5' \
  --header 'X-PerseusClientId: 1632821284775.1682808939.pcqscvuyjf' \
  --header 'X-PerseusSessionId: 1632822120625.8832869075.bkheoxpobq'
```

`X-Device-Source` is required — the plugin maps it to a path segment and only accepts
the iOS/Android values; anything else yields an empty segment and a 400 (`Device Source
cannot be empty!`). `lat`, `lon` and `area_id` are validated the same way.

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

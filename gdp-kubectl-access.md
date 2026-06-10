# Accessing GDP Pods via kubectl

## Prerequisites

- [dp-devinfra CLI](https://dev.deliveryhero.net/catalog/default/group/developer-platform/docs) installed
- [okta-aws-cli](https://github.com/okta/okta-aws-cli) installed
- [kubectx](https://github.com/ahmetb/kubectx) (optional, for easy context switching)
- You must be a **Direct Contributor** (rw) or **Inherited Contributor** (ro) of the application on [DevHub](https://dev.deliveryhero.net)
- The application must be successfully deployed in at least one environment

## Step 1: Generate Configurations

Run this once (or whenever your destinations change):

```bash
dp-devinfra destinations create-configs
```

This generates AWS CLI, gcloud CLI, and kubectl configurations for all destinations you have access to.

## Step 2: Find Your Application

```bash
# List deployments for your app
dp-devinfra deployments list --app <app-name>

# Example
dp-devinfra deployments list --app tlb-deals-bff
```

This shows the stamp and environment for each deployment.

## Step 3: Switch Context and Authenticate

Add this helper to your `~/.zshrc`:

```bash
function gdp-access() {
  eval "$(dp-devinfra destinations access --export-env-vars "$1" "$2" "$3")"
}
```

Then run:

```bash
# Usage: gdp-access <platform> <environment> <stamp>
gdp-access talabat production standard
```

Or without the helper:

```bash
dp-devinfra destinations access talabat production standard
```

After this, set the AWS profile as instructed:

```bash
export AWS_PROFILE=<account-id>
export AWS_REGION=eu-west-2
```

## Step 4: Access Pods

```bash
# List pods in your app namespace (namespace = app name)
kubectl get pods -n <app-name>

# Example
kubectl get pods -n tlb-deals-bff

# View app container logs
kubectl logs -n <app-name> <pod-name> -c <container-name> --tail=100

# View STS sidecar logs
kubectl logs -n <app-name> <pod-name> -c sts --tail=50

# Exec into a pod
kubectl exec -it -n <app-name> <pod-name> -c <container-name> -- /bin/sh
```

## Alternative: Using saml2aws (when dp-devinfra flow fails)

If the `dp-devinfra` flow doesn't work (e.g., timeouts, auth issues), you can use `saml2aws` directly. This was the approach Yigi helped set up.

### Prerequisites

- [saml2aws](https://github.com/Versent/saml2aws) installed (`brew install saml2aws`)

### Step A: Disable Cloudflare WARP

**This is critical.** GDP EKS clusters have private API endpoints and WARP IPs may not be whitelisted.

1. Open Cloudflare WARP client
2. Toggle it **OFF** (disconnect)
3. Make sure you're on office network or a network that can reach the EKS API

### Step B: Configure saml2aws profile

Add a GDP-specific profile to `~/.saml2aws`. Back up first:

```bash
cp ~/.saml2aws ~/.saml2aws_bkup
```

Add/edit the following profile (replace username with yours):

```ini
[tlb-gdp-production]
name                    = tlb-gdp-production
url                     = https://deliveryhero.okta.com/home/amazon_aws/0oaafbf2n0igEw89O416/272
username                = avijeet.gaikwad@talabat.com
provider                = Okta
mfa                     = Auto
skip_verify             = false
timeout                 = 0
aws_urn                 = urn:amazon:webservices
aws_session_duration    = 3600
aws_profile             = tlb-gdp-production
role_arn                = arn:aws:iam::457710302499:role/dp-avijeet-gaikwad-talabat-com-rw
saml_cache              = false
disable_remember_device = false
disable_sessions        = false
download_browser_driver = false
headless                = false
```

> **Note:** The `role_arn` follows the pattern `dp-<your-email-with-hyphens>-rw`. The account ID `457710302499` is for talabat production.

### Step C: Login with saml2aws

```bash
saml2aws login -a "tlb-gdp-production" --username="avijeet.gaikwad@talabat.com"
```

This opens a browser for Okta MFA. After authentication, AWS credentials are written to `~/.aws/credentials` under the `tlb-gdp-production` profile.

### Step D: Update kubeconfig for the GDP cluster

```bash
aws eks update-kubeconfig --region eu-west-2 --name special-ghost --profile tlb-gdp-production
```

> The cluster name (e.g., `special-ghost`) comes from your app's deployment destination. You can find it via `dp-devinfra deployments list --app <app-name>`.

### Step E: Access pods

```bash
# List pods
kubectl get pods -n tlb-deals-bff

# Get container names for a pod
kubectl get pod -n tlb-deals-bff <pod-name> -o jsonpath='{.spec.containers[*].name}'

# Exec into the main container
kubectl -n=tlb-deals-bff exec -it -c=tlb-deals-bff-csam-deals-bff-svc-main <pod-name> -- /bin/sh

# Run curl from inside the pod (if curl is available)
# Or spin up a temporary curl pod in the same namespace:
kubectl run -n tlb-deals-bff curl-test --rm -it --image=curlimages/curl -- sh
```

---

## Troubleshooting

### Timeout: `dial tcp ...:443: i/o timeout`

The GDP EKS clusters have private API endpoints. Possible causes:

- **Cloudflare WARP VPN** IPs may not be whitelisted. **Disable WARP first** — this is the most common cause.
- Your office IP may not be whitelisted. Raise a request in [#gdp-support](https://deliveryhero.slack.com/archives/C06JWKPPAHK).

### `unable to find any tenant`

Wrong platform/environment/stamp combination. Run `dp-devinfra deployments list --app <app-name>` to find the correct values.

### `Unauthorized` or `Forbidden`

- Ensure you are a contributor on the app in DevHub.
- Delete cached credentials and re-authenticate:
  ```bash
  rm -rf ~/.aws/okta-cache
  dp-devinfra destinations create-configs
  ```

### saml2aws session expired

Sessions last 1 hour (`aws_session_duration = 3600`). Re-run:
```bash
saml2aws login -a "tlb-gdp-production" --username="avijeet.gaikwad@talabat.com"
```

## Reference

- [GDP Accessing Infrastructure Docs](https://dev.deliveryhero.net/docs/default/group/developer-platform/user-guides/accessing-infrastructure/)
- [#gdp-support Slack channel](https://deliveryhero.slack.com/archives/C06JWKPPAHK)
- [#tlb_gdp_adoption Slack channel](https://deliveryhero.slack.com/archives/C08K3M0M1JP)

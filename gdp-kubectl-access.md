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

## Troubleshooting

### Timeout: `dial tcp ...:443: i/o timeout`

The GDP EKS clusters have private API endpoints. Possible causes:

- **Cloudflare WARP VPN** IPs may not be whitelisted. Try disconnecting WARP and using office network directly.
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

## Reference

- [GDP Accessing Infrastructure Docs](https://dev.deliveryhero.net/docs/default/group/developer-platform/user-guides/accessing-infrastructure/)
- [#gdp-support Slack channel](https://deliveryhero.slack.com/archives/C06JWKPPAHK)
- [#tlb_gdp_adoption Slack channel](https://deliveryhero.slack.com/archives/C08K3M0M1JP)

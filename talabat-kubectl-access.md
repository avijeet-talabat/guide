# Accessing Talabat Legacy Pods via kubectl

## Prerequisites

- [saml2aws](https://github.com/Versent/saml2aws) installed and configured
- kubectl installed
- [kubectx](https://github.com/ahmetb/kubectx) (optional, for easy context switching)

## Step 1: Authenticate with AWS via saml2aws

```bash
# Production
saml2aws login -a tlb-prd-2

# QA
saml2aws login -a tlb-qa
```

This authenticates via Okta and stores temporary AWS credentials.

## Step 2: Update kubeconfig

```bash
# Production main cluster
aws eks update-kubeconfig --region eu-west-2 --name talabat-prod-main-cluster --profile tlb-prd-2

# Production failover cluster
aws eks update-kubeconfig --region eu-west-2 --name talabat-prod-failover-cluster --profile tlb-prd-2

# QA clusters
aws eks update-kubeconfig --region eu-west-2 --name talabat-qa-eks-az-2a-cluster --profile tlb-qa
aws eks update-kubeconfig --region eu-west-2 --name talabat-qa-eks-az-2b-cluster --profile tlb-qa
```

## Step 3: Switch Context

```bash
# List available contexts
kubectl config get-contexts

# Switch to production
kubectx arn:aws:eks:eu-west-2:457710302499:cluster/talabat-prod-main-cluster

# Switch to QA
kubectx arn:aws:eks:eu-west-2:690772145391:cluster/talabat-qa-eks-az-2a-cluster
```

## Step 4: Access Pods

```bash
# List namespaces
kubectl get namespaces

# List pods in a namespace
kubectl get pods -n <namespace>

# Example: find pods by name
kubectl get pods -n growth | grep offer

# View logs
kubectl logs -n <namespace> <pod-name> --tail=100

# Exec into a pod
kubectl exec -it -n <namespace> <pod-name> -- /bin/sh

# Follow logs in real-time
kubectl logs -n <namespace> <pod-name> -f
```

## Useful Commands

```bash
# Get all pods across namespaces matching a pattern
kubectl get pods --all-namespaces | grep <pattern>

# Describe a pod (events, status, containers)
kubectl describe pod -n <namespace> <pod-name>

# Port-forward to a pod
kubectl port-forward -n <namespace> <pod-name> <local-port>:<pod-port>
```

## Troubleshooting

### Credentials expired

saml2aws credentials expire after a session. Re-run:

```bash
saml2aws login -a tlb-prd-2
```

### Wrong cluster

Check which context you're on:

```bash
kubectx --current
```

### Cannot find pods

Services on GDP (Global Deployment Platform) are **not** on the legacy clusters. Use the [GDP access guide](gdp-kubectl-access.md) instead.

# Build .NET Service Locally

## Step 1: Authenticate with AWS via Okta

```bash
okta-aws-cli --org-domain deliveryhero.okta.com --oidc-client-id 0oa8auoikj3oPvy4b417 --write-aws-credentials --open-browser --profile tlb-dev-2
```

When prompted, choose:
- IdP: `arn:aws:iam::690772145391:saml-provider/DH_Okta`
- Role: `arn:aws:iam::690772145391:role/growth`

## Step 2: Login to CodeArtifact

```bash
aws codeartifact login --tool dotnet --domain tlb-test-code-artifact-domain --repository internal-nuget-repo --domain-owner 690772145391 --region eu-west-2 --profile tlb-dev-2
```

You should see: `Successfully configured nuget to use AWS CodeArtifact repository...`

## Step 3: Build

```bash
dotnet restore
dotnet build
```

## Notes

- The CodeArtifact token expires after **12 hours** — re-run step 2 when it expires
- If `okta-aws-cli` is not installed, follow [this guide](https://github.com/okta/okta-aws-cli) to install it
- Verify your AWS auth with: `aws sts get-caller-identity --profile tlb-dev-2`

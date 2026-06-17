# 1. Prerequisites

> **Platform:** Steps below assume **OpenShift** and the `oc` CLI. The workshop is a **Backstage** workshop delivered with **Red Hat Developer Hub**; the same catalog, app-config, and plugin patterns apply to Community Backstage on vanilla Kubernetes — use `kubectl` where this guide says `oc`, and adapt Routes to Ingress or port-forwarding. See [TUTORIAL.md — Developer Hub and Backstage](TUTORIAL.md#developer-hub-and-backstage).

## Cluster access

- OpenShift 4.x cluster with a dedicated namespace/project
- `oc` CLI logged in
- Permissions in your namespace to create:
  - Deployments, Services, Routes, PVCs, Secrets, BuildConfigs
  - Operator Subscriptions (for GitOps and Developer Hub operators) **or** Helm releases

## Local tools

Workshop scripts require **bash 4+** and run on **macOS and Linux** (including Red Hat Developer Sandbox / RHDAT). Run `./scripts/bootstrap-workshop.sh` — do not invoke with `sh`.

| Tool | Used for |
|------|----------|
| `bash` | All workshop scripts (`scripts/lib/common.sh` provides portable helpers) |
| `oc` | Applying manifests, builds, validation |
| `curl` | API and health checks |
| `jq` | JSON output in validation scripts |
| `envsubst` | Optional — scripts use `workshop_envsubst` in `common.sh` (gettext when installed, bash fallback otherwise) |
| `helm` | Helm install path only ([03b-install-with-helm](03b-install-with-helm.md)) |

Optional:

| Tool | Used for |
|------|----------|
| `git`, `mvn`, `node` | Local application development |
| Python 3.9+, Chrome | `./e2e/run-e2e.sh` end-to-end tests |

## Fork the repository

Fork [platform-engineering-201](https://github.com/maarten-vandeperre/platform-engineering-201) to your GitHub organization and update `scripts/workshop.env`:

- `WORKSHOP_GIT_REPO` — clone URL of your fork
- `WORKSHOP_GITHUB_ORG` / `WORKSHOP_GITHUB_REPO` — used for catalog annotations such as `github.com/project-slug` (rendered via `workshop_envsubst`; not hard-coded in YAML)
- `CLUSTER_ROUTER_BASE` — your OpenShift apps domain

## GitHub token (required for scaffolder publish)

The scaffolder **Fetch skeleton** step reads from GitHub without a PAT (public repo). **Publish to GitHub** requires a server-side PAT with `repo` scope.

Configure OAuth and PAT together:

```bash
./scripts/setup-github-auth.sh --open-pat-url
```

Or set the token explicitly:

```bash
GITHUB_TOKEN=ghp_... ./scripts/setup-github-auth.sh --no-interactive
```

Create a classic PAT at [github.com/settings/tokens](https://github.com/settings/tokens/new?scopes=repo,workflow) with:

- `repo` (for private repos) or public repo access
- `workflow` (read Actions)

Export before bootstrap or Developer Hub setup:

```bash
export GITHUB_TOKEN=ghp_...
```

The token is stored in the `app-secrets-rhdh` / `rhdh-workshop-secrets` Secret.

## GitHub OAuth App (required for CI tab)

The **GitHub Actions CI tab** prompts users to **Authorize GitHub** in a popup. That flow needs a **GitHub OAuth App** (not the same as a PAT).

1. Create an app at [GitHub → Developer settings → OAuth Apps → New](https://github.com/settings/applications/new)
2. Set **Authorization callback URL** to:

   ```text
   https://redhat-developer-hub-<namespace>.<router>/api/auth/github/handler/frame
   ```

   Example:

   ```text
   https://redhat-developer-hub-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com/api/auth/github/handler/frame
   ```

3. Add to `scripts/workshop.env`:

   ```bash
   export AUTH_GITHUB_CLIENT_ID="Ov23li..."
   export AUTH_GITHUB_CLIENT_SECRET="..."
   export GITHUB_TOKEN="ghp_..."
   ```

   Or run the helper script (opens GitHub, saves credentials, applies Developer Hub config):

   ```bash
   ./scripts/create-github-oauth-app.sh --oauth-app
   ```

   Fully automated alternative (creates a GitHub App with OAuth credentials):

   ```bash
   ./scripts/create-github-oauth-app.sh
   ```

4. Apply (if you did not use the create script):

   ```bash
   source scripts/workshop.env
   ./scripts/setup-github-auth.sh --oauth-only
   ```

If `client_id=changeme` appears in the authorize URL, GitHub returns **404** — run `./scripts/create-github-oauth-app.sh --oauth-app` first.

### Reusing an existing OAuth App

The create script **does not delete** OAuth Apps on GitHub. To reuse an app you already registered:

```bash
# credentials already in scripts/workshop.env
source scripts/workshop.env
./scripts/setup-github-auth.sh --oauth-only
```

Use `./scripts/create-github-oauth-app.sh` only for **first-time setup** or when you need **new** credentials. Re-running `--oauth-app` opens the registration form again; paste your existing Client ID and secret instead of creating a duplicate app.

If you lost the client secret, generate a new one on the [OAuth App settings page](https://github.com/settings/developers), update `AUTH_GITHUB_CLIENT_SECRET` in `workshop.env`, then run `./scripts/setup-github-auth.sh --oauth-only`.

## Namespace and cluster domain

Default namespace: `rh-ee-mvandepe-dev`.

Change it in `scripts/workshop.env`:

```bash
export WORKSHOP_NAMESPACE=your-namespace
export CLUSTER_ROUTER_BASE=apps.your-cluster.example.com
```

`CLUSTER_ROUTER_BASE` is the shared suffix for OpenShift routes (the part after the first hostname label). Example: for route `people-frontend-myns.apps.rm1.example.com`, set `CLUSTER_ROUTER_BASE=apps.rm1.example.com`.

## Next step

[2. Configure the workshop](02-configuration.md)

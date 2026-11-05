---
next: /docs/advanced-topics
prev: /docs
title: Getting started
weight: 1
---

## Usage

{{% steps %}}

### Prepare the Azure DevOps organization

Create [a new agent pool](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/pools-queues) in Azure DevOps. Then, create [the personal access token](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/personal-access-token-agent-registration?view=azure-devops), with the scope `agent pools (read & manage)`, allowing access from the agent to Azure DevOps.

On Kubernetes, agents can register without a PAT: with a Microsoft Entra service principal and a client secret, or with a workload identity and no secret at all (see [below](#with-a-workload-identity) and the [dedicated section](../advanced-topics/service-principal)).

### Deploy

Software can either be deployed using Helm on a Kubernetes cluster or Bicep on Azure Container Apps.

{{% /steps %}}

## Deploy on Azure

{{< callout type="info" >}}
Azure deployment has a limitation regarding the demands and the OS:

- OS are limited to Linux, such as Debian, as Azure Containers Apps does not support Windows.
- The agent will not be able to run jobs requiring a system demand, such as `Agent.OS` or `Agent.OSArchitecture`. However, user-defined demands from the `pipelinesCapabilities` parameter are usable.

{{< /callout >}}

Deployment is using Bicep as a template language. Minimal configuration is required:

```bash
az deployment sub create \
  --location westeurope \
  --name blue-agent \
  --parameters \
    pipelinesOrganizationURL=https://dev.azure.com/your-organization \
    pipelinesPersonalAccessToken=your-pat \
    pipelinesPoolName=your-pool \
  --template-file src/bicep/main.bicep
```

The deployment will manage the resource provisioning, in a dedicated resource group. This includes (but is not limited to) Container Apps and Log Analytics.

Details about the Helm configuration [can be found in a dedicated section](../advanced-topics/bicep-deployment).

## Deploy on Kubernetes

{{% steps %}}

### Prepare the Helm values

Minimal configuration is required:

```yaml
# values.yaml
image:
  flavor: trixie
pipelines:
  organizationURL: https://dev.azure.com/your-organization
  personalAccessToken: your-pat
  poolName: your-pool
```

Set `image.flavor` explicitly, the chart default (`bookworm`) is deprecated, see the [OS support matrix](#os-support-matrix). Details about the Helm configuration [can be found in a dedicated section](../advanced-topics/helm-values).

Auto-scaling requires [KEDA](https://keda.sh) in the cluster (KEDA >= 2.21 for the service principal authentication and for scheduled warm agents), [see scaling](../advanced-topics/scaling). Without KEDA, set `autoscaling.enabled: false` to deploy a fixed number of agents.

#### With a workload identity

The agent exchanges the token of its Kubernetes service account for a Microsoft Entra access token, on AKS or any cluster whose OIDC issuer is trusted by Microsoft Entra ID (EKS, GKE, on-premises). Prerequisites:

- the [Azure Workload Identity webhook](https://azure.github.io/azure-workload-identity/docs/installation.html) on the cluster (built in on AKS with `--enable-workload-identity`);
- an app registration or a user-assigned managed identity, with a federated credential for the agent service account (`system:serviceaccount:<namespace>:<release service account>`) and one for the KEDA operator (`system:serviceaccount:<keda namespace>:keda-operator`, with `podIdentity.azureWorkload.enabled: true` in the KEDA chart);
- the identity added to the Azure DevOps organization (_Basic_ access level), with the _Administrator_ role on the agent pool.

```yaml
# values.yaml
image:
  flavor: noble
pipelines:
  organizationURL: https://dev.azure.com/your-organization
  poolName: your-pool
  auth:
    type: workloadIdentity
    clientId: your-client-id
```

From 13.2.1, the variables injected by the webhook are not passed to the jobs, so the pipeline service connections keep their own identity. Details in [service principal and workload identity](../advanced-topics/service-principal).

### Install the chart

Use Helm to install the latest released chart, published as an OCI artifact on GitHub Container Registry:

```bash
helm upgrade --install agent oci://ghcr.io/kamorionlabs/charts/blue-agent --values values.yaml
```

A specific version can be pinned with `--version` (e.g. `--version 13.1.0`). Charts up to `12.0.1` were published by the original project and are not republished here.

{{% /steps %}}

## Template Container Behavior

When deploying Blue Agent with KEDA auto-scaling enabled, a "template" container will run briefly during deployment. This is expected behavior that registers agent capabilities with Azure DevOps and enables KEDA scaling. The template container runs for 1 minute then stops (remaining as "offline" in the agent pool).

For detailed information about template container behavior, common errors, and troubleshooting, see the [troubleshooting documentation](../troubleshooting).

## OS support matrix

OS support is generally called "flavor" in this documentation. The following table shows the supported flavors and their characteristics.

{{< callout type="warning" >}}
The `jammy`, `ubi8` and `bookworm` flavors are deprecated and will be removed in v14.0.0. Migrate to `noble` or `resolute`, `ubi9` or `ubi10`, and `trixie` respectively.
{{< /callout >}}

| `Ref`                                               | OS                                                                                   | `Arch`              | Support                                                                                                                                           |
| --------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ghcr.io/kamorionlabs/blue-agent:alpine-main`       | [Alpine Linux (3.24)](https://alpinelinux.org/posts/Alpine-3.24.0-released.html)     | `amd64`, `arm64/v8` | [See Alpine Linux wiki.](https://alpinelinux.org/releases)                                                                                        |
| `ghcr.io/kamorionlabs/blue-agent:azurelinux3-main`  | [Azure Linux 3](https://github.com/microsoft/azurelinux)                             | `amd64`, `arm64/v8` | [See Microsoft Azure documentation.](https://learn.microsoft.com/en-us/azure/aks/support-policies)                                                |
| `ghcr.io/kamorionlabs/blue-agent:bookworm-main`     | [Debian Bookworm (12)](https://www.debian.org/releases/bookworm) slim (deprecated)   | `amd64`, `arm64/v8` | [See Debian LTS wiki.](https://wiki.debian.org/LTS)                                                                                               |
| `ghcr.io/kamorionlabs/blue-agent:trixie-main`       | [Debian Trixie (13)](https://www.debian.org/releases/trixie) slim                    | `amd64`, `arm64/v8` | [See Debian LTS wiki.](https://wiki.debian.org/LTS)                                                                                               |
| `ghcr.io/kamorionlabs/blue-agent:resolute-main`     | [Ubuntu Resolute (26.04)](https://www.releases.ubuntu.com/resolute) minimal          | `amd64`, `arm64/v8` | [See Ubuntu LTS wiki.](https://wiki.ubuntu.com/Releases)                                                                                          |
| `ghcr.io/kamorionlabs/blue-agent:noble-main`        | [Ubuntu Noble (24.04)](https://www.releases.ubuntu.com/noble) minimal                | `amd64`, `arm64/v8` | [See Ubuntu LTS wiki.](https://wiki.ubuntu.com/Releases)                                                                                          |
| `ghcr.io/kamorionlabs/blue-agent:jammy-main`        | [Ubuntu Jammy (22.04)](https://www.releases.ubuntu.com/jammy) minimal (deprecated)   | `amd64`, `arm64/v8` | [See Ubuntu LTS wiki.](https://wiki.ubuntu.com/Releases)                                                                                          |
| `ghcr.io/kamorionlabs/blue-agent:ubi10-main`        | [Red Hat UBI 10](https://developers.redhat.com/articles/ubi-faq) minimal             | `amd64`, `arm64/v8` | [See Red Hat product life cycles.](https://access.redhat.com/product-life-cycles/?product=Red%20Hat%20Enterprise%20Linux)                         |
| `ghcr.io/kamorionlabs/blue-agent:ubi9-main`         | [Red Hat UBI 9](https://developers.redhat.com/articles/ubi-faq) minimal              | `amd64`, `arm64/v8` | [See Red Hat product life cycles.](https://access.redhat.com/product-life-cycles/?product=Red%20Hat%20Enterprise%20Linux)                         |
| `ghcr.io/kamorionlabs/blue-agent:ubi8-main`         | [Red Hat UBI 8](https://developers.redhat.com/articles/ubi-faq) minimal (deprecated) | `amd64`             | [See Red Hat product life cycles.](https://access.redhat.com/product-life-cycles/?product=Red%20Hat%20Enterprise%20Linux)                         |
| `ghcr.io/kamorionlabs/blue-agent:win-ltsc2022-main` | [Windows Server 2022](https://learn.microsoft.com/en-us/windows-server) Core         | `amd64`             | [See base image servicing lifecycles.](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/base-image-lifecycle) |
| `ghcr.io/kamorionlabs/blue-agent:win-ltsc2025-main` | [Windows Server 2025](https://learn.microsoft.com/en-us/windows-server) Core         | `amd64`             | [See base image servicing lifecycles.](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/base-image-lifecycle) |

The `ubi8` flavor is built for `amd64` only: PowerShell Linux `arm64` releases need glibc 2.33 or later since 7.4.20, and UBI 8 ships glibc 2.28. Use `ubi9` for Red Hat on `arm64`.

## Container registries

Container images are published to GitHub Container Registry, at `ghcr.io/kamorionlabs/blue-agent`. Each image is tagged `<flavor>-<version>` (e.g. `trixie-13.1.0`), the Helm chart uses the tag matching its own version by default (see `image.version`). Rolling tags are also available: `<flavor>-latest` (latest release), `<flavor>-<major>` and `<flavor>-<major>.<minor>`, `<flavor>-main` (development branch). Each release build is also tagged with its build date, `<flavor>-<version>-<YYYYMMDD>`, as release images are rebuilt every month ([see security](../security#reliability-notes)).

Linux images are multi-architecture (`amd64` and `arm64`, except `ubi8`), Windows images are `amd64` only. Images and the chart are signed with Cosign keyless signatures, [see how to verify them](../security#chain-of-trust).

Images up to `12.0.1` were published by the original project at `ghcr.io/clemlesne/blue-agent` and `docker.io/clemlesne/blue-agent`, they are not maintained anymore.

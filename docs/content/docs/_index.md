---
linkTitle: Documentation
next: /docs/getting-started
title: Introduction
---

Blue Agent is self-hosted Azure Pipelines agent in Kubernetes, cheap to run, secure, auto-scaled and easy to deploy.

{{< callout type="info" >}}
This is the [KamorionLabs](https://github.com/KamorionLabs) fork of [clemlesne/blue-agent](https://github.com/clemlesne/blue-agent), created by Clémence Lesné and not maintained anymore since mid-2025. Releases continue from `13.0.0`, images are published to `ghcr.io/kamorionlabs/blue-agent` and the Helm chart to `oci://ghcr.io/kamorionlabs/charts/blue-agent`. See [about](../about).
{{< /callout >}}

## Features

- 🏗️ Allow to build containers inside the agent using [BuildKit](https://github.com/moby/buildkit).
- 💪 Performances can be customized depending of the engineering needs, which goes far beyond the Microsoft-hosted agent.
- 📵 Can run air-gapped (no internet access).
- 🔄 Agent register and restart itself, with the [Azure Pipelines agent](https://github.com/microsoft/azure-pipelines-agent) v5.
- 🔑 Agents register with a personal access token (PAT), a Microsoft Entra service principal or a workload identity ([see authentication](advanced-topics/service-principal)).
- 📈 Auto-scaling with [KEDA](https://keda.sh), from zero, with scheduled warm agents, an idle timeout and custom triggers ([see scaling](advanced-topics/scaling)).
- 🪙 Ready for spot nodes, with node selectors, tolerations, affinity, topology spread constraints and priority classes ([see spot instances](advanced-topics/spot-instances)).
- 🔧 Packaged with common automation tools ([jq](https://github.com/stedolan/jq), [PowerShell Core](https://github.com/PowerShell/PowerShell), [Python 3](https://python.org), [rsync](https://rsync.samba.org), ...) and .NET 10 ([see provided software](advanced-topics/provided-software)).
- 🖥️ Available with [Alpine Linux](https://alpinelinux.org), [Azure Linux](https://github.com/microsoft/azurelinux), [Debian](https://debian.org), [Ubuntu](https://ubuntu.com), [Red Hat Enterprise Linux](https://access.redhat.com/products/red-hat-enterprise-linux) and [Windows Server](https://www.microsoft.com/en-us/windows-server), on `amd64` and `arm64` ([see flavors](getting-started#os-support-matrix)).

## Best practices for safety

- 💰 Cheap to run (dynamic provisioning of agents, can scale from 0 to 100+ in few seconds with [KEDA](https://keda.sh)).
- 📦 [SBOM (Software Bill of Materials)](https://en.wikipedia.org/wiki/Software_supply_chain) is packaged with each container image.
- 🔄 Released images are rebuilt every month to pick up base image security fixes.
- 🔒 Build authenticity can be cryptographically verified with [Cosign](https://github.com/sigstore/cosign) keyless signatures ([Sigstore](https://www.sigstore.dev)).
- 🪶 Slim container images by design.

## Next

{{< cards >}}
{{< card link="getting-started" title="Getting started" icon="check" subtitle="Quick steps to deploy" >}}
{{< card link="advanced-topics/helm-values" title="Helm values" icon="adjustments" subtitle="Every value of the chart, with its default" >}}
{{< card link="advanced-topics/scaling" title="Scaling" icon="trending-up" subtitle="KEDA, warm agents on a schedule, idle timeout" >}}
{{< card link="security" title="Security" icon="shield-check" subtitle="Chain of trust & reporting a vulnerability" >}}
{{< /cards >}}

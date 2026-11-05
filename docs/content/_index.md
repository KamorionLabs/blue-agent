---
title: Blue Agent
layout: hextra-home
---

<div class="hx-mt-6">
{{< hextra/hero-badge link="about" >}}
  KamorionLabs fork of clemlesne/blue-agent
{{< /hextra/hero-badge >}}
</div>

<div class="hx-mt-4 hx-mb-6">
{{< hextra/hero-headline >}}
  Azure Pipelines agents<br class="sm:block hidden" />in Kubernetes
{{< /hextra/hero-headline >}}
</div>

<div class="hx-mb-12">
{{< hextra/hero-subtitle >}}
  Blue Agent is self-hosted Azure Pipelines agent in Kubernetes, cheap to run, secure, auto-scaled and easy to deploy. Linux and Windows, amd64 and arm64.
{{< /hextra/hero-subtitle >}}
</div>

<div class="hx-mb-6">
{{< hextra/hero-button text="Get started" link="docs/getting-started" >}}
</div>

<div class="content hx-mb-12 hx-w-full">

```bash
helm upgrade --install agent oci://ghcr.io/kamorionlabs/charts/blue-agent --values values.yaml
```

</div>

{{< hextra/feature-grid >}}
{{< hextra/feature-card title="Linux and Windows" icon="server" link="docs/getting-started#os-support-matrix" subtitle="`alpine`, `azurelinux3`, `trixie`, `noble`, `resolute`, `ubi9` and `ubi10` on amd64 and arm64, `win-ltsc2022` and `win-ltsc2025` on amd64. Images at `ghcr.io/kamorionlabs/blue-agent`." >}}
{{< hextra/feature-card title="Authentication" icon="key" link="docs/advanced-topics/service-principal" subtitle="Agents register with a personal access token, a Microsoft Entra service principal or a workload identity." >}}
{{< hextra/feature-card title="Auto-scaling" icon="trending-up" link="docs/advanced-topics/scaling" subtitle="Scale from zero with KEDA, keep warm agents on a schedule, recycle idle agents, add custom triggers." >}}
{{< hextra/feature-card title="Spot instances" icon="lightning-bolt" link="docs/advanced-topics/spot-instances" subtitle="Run agents on spot nodes with Karpenter or AKS spot node pools, with topology spread and priority classes." >}}
{{< hextra/feature-card title="Build containers" icon="cube" link="docs/advanced-topics/docker-in-docker" subtitle="Build container images inside the agent with BuildKit, rootless, on Linux flavors." >}}
{{< hextra/feature-card title="Signed supply chain" icon="shield-check" link="docs/security" subtitle="Images and Helm chart signed with Cosign keyless signatures, with SBOM and provenance, rebuilt every month." >}}
{{< /hextra/feature-grid >}}

<div class="content hx-mt-12 hx-text-sm">

Blue Agent was created by [Clémence Lesné](https://github.com/clemlesne) as [clemlesne/blue-agent](https://github.com/clemlesne/blue-agent), under the Apache License 2.0. This fork is maintained by [KamorionLabs](https://github.com/KamorionLabs) since the original project stopped being maintained, releases continue from `13.0.0`. [Read more](about).

</div>

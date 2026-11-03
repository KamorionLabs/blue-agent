> [!NOTE]
> This is the [KamorionLabs](https://github.com/KamorionLabs) fork of [clemlesne/blue-agent](https://github.com/clemlesne/blue-agent), see the [fork notice](#fork-notice).

# Blue Agent

<!-- Use absolute path for images in README.md, so that they are displayed on ArtifactHub.io, Lens, OpenLens, etc. -->
<img src="https://raw.githubusercontent.com/KamorionLabs/blue-agent/main/docs/static/favicon.svg" width="100">

[Blue Agent](https://github.com/KamorionLabs/blue-agent) is self-hosted agent in Kubernetes, cheap to run, secure, auto-scaled and easy to deploy.

<!-- github.com badges -->

[![Last release date](https://img.shields.io/github/release-date/KamorionLabs/blue-agent)](https://github.com/KamorionLabs/blue-agent/releases)
[![Project license](https://img.shields.io/github/license/KamorionLabs/blue-agent)](https://github.com/KamorionLabs/blue-agent/blob/main/LICENSE)

## Features

- 🏗️ Allow to build containers inside the agent using [BuildKit](https://github.com/moby/buildkit).
- 💪 Performances can be customized depending of the engineering needs, which goes far beyond the Microsoft-hosted agent.
- 📵 Can run air-gapped (no internet access).
- 🔄 Agent register and restart itself.
- 🔧 Packaged with common automation tools ([jq](https://github.com/stedolan/jq), [PowerShell Core](https://github.com/PowerShell/PowerShell), [Python 3](https://python.org), [rsync](https://rsync.samba.org), ...).
- 🖥️ Available with [Alpine Linux](https://alpinelinux.org), [Azure Linux](https://github.com/microsoft/azurelinux), [Debian](https://debian.org), [Ubuntu](https://ubuntu.com), [Red Hat Enterprise Linux](https://access.redhat.com/products/red-hat-enterprise-linux) and [Windows Server](https://www.microsoft.com/en-us/windows-server)

## Best practices for safety

- 💰 Cheap to run (dynamic provisioning of agents, can scale from 0 to 100+ in few seconds with [KEDA](https://keda.sh)).
- 📦 [SBOM (Software Bill of Materials)](https://en.wikipedia.org/wiki/Software_supply_chain) is packaged with each container image.
- 🔄 Released images are rebuilt every month to pick up base image security fixes.
- 🔒 Build authenticity can be cryptographically verified with [Cosign](https://github.com/sigstore/cosign) keyless signatures ([Sigstore](https://www.sigstore.dev)).
- 🪶 Slim container images by design.

## How to deploy

[Deployment is available](https://kamorionlabs.github.io/blue-agent/docs/getting-started) using Helm on a Kubernetes cluster or Bicep on Azure Container Apps.

```bash
helm upgrade --install agent oci://ghcr.io/kamorionlabs/charts/blue-agent
```

## Documentation

Documentation is available at [kamorionlabs.github.io/blue-agent](https://kamorionlabs.github.io/blue-agent/).

## Fork notice

Blue Agent was created by [Clémence Lesné](https://github.com/clemlesne) as [clemlesne/blue-agent](https://github.com/clemlesne/blue-agent) (itself derived from [emberstack/docker-azure-pipelines-agent](https://github.com/emberstack/docker-azure-pipelines-agent)), under the [Apache License 2.0](./LICENSE). All credit for the project goes to its original authors, see [`NOTICE`](./NOTICE) and [`AUTHORS.md`](./AUTHORS.md).

The original project is not maintained anymore since mid-2025. This fork is maintained by [KamorionLabs](https://github.com/KamorionLabs) and is not affiliated with or endorsed by the original authors. Differences with the original project:

- Container images are published to `ghcr.io/kamorionlabs/blue-agent` (same `<flavor>-<version>` tags), the Helm chart to `oci://ghcr.io/kamorionlabs/charts/blue-agent`.
- Releases continue from `13.0.0`, versions up to `12.0.1` are the original project's releases.
- Images and chart are signed with Cosign keyless signatures (Sigstore), the original project's Cosign and GPG keys are not used anymore.

## [Code of conduct](./CODE_OF_CONDUCT.md)

## [Authors](./AUTHORS.md)

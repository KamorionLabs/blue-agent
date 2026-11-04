---
title: Provided software
---

Softwares are operating system specific. The following table lists the softwares provided by the agent.

#### Linux

- [Azure Pipelines agent](https://github.com/microsoft/azure-pipelines-agent) + [requirements](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/docker?view=azure-devops#linux)
- [BuildKit](https://github.com/moby/buildkit) + requirements ([dbus-user-session](https://dbus.freedesktop.org), [fuse-overlayfs](https://github.com/containers/fuse-overlayfs), [iptables](https://www.netfilter.org/projects/iptables/index.html), [shadow-utils](https://github.com/shadow-maint/shadow), [uidmap](https://github.com/shadow-maint/shadow))
- Cloud providers CLIs
  - [AWS CLI](https://github.com/aws/aws-cli)
  - [Azure CLI](https://github.com/Azure/azure-cli)
  - [Google Cloud SDK](https://cloud.google.com/sdk)
- Shells
  - [bash](https://www.gnu.org/software/bash) (default)
  - [PowerShell Core](https://github.com/PowerShell/PowerShell)
  - [zsh](https://www.zsh.org)
- Programming languages
  - [ASP.NET Core Runtime](https://github.com/dotnet/aspnetcore) ([dedicated section](./build-aspnet.md))
  - [Python 3](https://python.org) ([dedicated section](./build-python.md))
- Tools
  - [dnsutils](https://www.isc.org/bind)
  - [git](https://github.com/git-for-windows/git)
  - [gzip](https://www.gnu.org/software/gzip)
  - [jq](https://github.com/stedolan/jq)
  - [make](https://www.gnu.org/software/make)
  - [openssl](https://www.openssl.org)
  - [rsync](https://rsync.samba.org)
  - [tar](https://www.gnu.org/software/tar)
  - [unzip](https://infozip.sourceforge.net/UnZip.html)
  - [wget](https://www.gnu.org/software/wget)
  - [yq](https://github.com/mikefarah/yq)
  - [zip](https://infozip.sourceforge.net/Zip.html)
  - [zstd](https://github.com/facebook/zstd)

#### Linux Node.js task runners

Linux images ship the Azure Pipelines agent with the Node.js 20 and 24 task runners only. The end-of-life Node.js 6, 10 and 16 runners are not included: glibc flavors use the `pipelines-agent` package, which does not bundle them, and the `alpine` flavor removes them from the musl `vsts-agent` package, as Microsoft publishes no musl `pipelines-agent` package.

Tasks declaring a Node.js 20 or 24 handler are not affected. A task declaring only an end-of-life handler (`Node`, `Node10` or `Node16` in its `task.json`) fails with `This step requires a node version that does not exist in the agent filesystem`. Upgrade the task to a recent major version, or force a supported runner with a pipeline variable (or the same environment variable on the agent, see `extraEnv` in the Helm chart):

```yaml
# azure-pipelines.yaml (extract)
variables:
  AGENT_USE_NODE24: true
```

{{< callout type="warning" >}}
`AGENT_USE_NODE24` (or `AGENT_USE_NODE20_1`) runs every Node.js task of the job on that runner. Tasks written for an older Node.js version usually work, but this is not guaranteed.
{{< /callout >}}

#### Windows

- [Azure Pipelines agent](https://github.com/microsoft/azure-pipelines-agent) + [requirements](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/docker?view=azure-devops#linux)
- Cloud providers CLIs
  - [AWS CLI](https://github.com/aws/aws-cli)
  - [Azure CLI](https://github.com/Azure/azure-cli)
  - [Google Cloud SDK](https://cloud.google.com/sdk)
- Shells
  - [PowerShell Core](https://github.com/PowerShell/PowerShell) (default)
  - [Windows PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/windows-powershell/install/installing-windows-powershell?view=powershell-7.3)
- Programming languages
  - [.NET SDK](https://dotnet.microsoft.com) ([dedicated section](./build-aspnet.md))
  - [Python 3](https://python.org) ([dedicated section](./build-python.md))
  - [Visual Studio Build Tools (LTSC 17.12)](https://learn.microsoft.com/en-us/visualstudio/ide/?view=vs-2022) (with `AzureBuildTools`, `VCTools`, `WebBuildTools`, `ManagedDesktopBuildTools`, `OfficeBuildTools` workloads)
- Tools
  - [git](https://github.com/git-for-windows/git)
  - [jq](https://github.com/stedolan/jq)
  - [yq](https://github.com/mikefarah/yq)
  - [zstd](https://github.com/facebook/zstd)

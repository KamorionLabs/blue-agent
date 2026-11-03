---
title: Performance
---

These actions can enhance your system performance:

- Enough CPU and memory are allocated to the agent (see `resources`). See the your Kubernetes monitoring software to detect bottlenecks (notably CPU, RAM, IOPS, network, disk size).
- No `emptyDir` is used (see `pipelines.cache.volumeEnabled`, `pipelines.tmpdir.volumeEnabled`, and `extraVolumes`).
- SSD volumes are used for both cache (see `pipelines.cache`) and system temporary directory (see `pipelines.tmpdir`). For exemple, in Azure, the `managed-csi-premium` StorageClass is a high-performance SSD; in AWS, a `gp3` StorageClass with provisioned IOPS and throughput.
- The network bewteen Azure DevOps server and agents has a low latency.

BuikdKit specifics:

- Choose an ephemeral disk for the cache in `/app-root/.local/share/buildkit`, instead of an emptyDir.
- Use an high-performance disk for the cache, exemple `managed-csi-premium` in Azure.

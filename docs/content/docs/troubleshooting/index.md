---
prev: /docs/security
title: Troubleshooting
weight: 5
---

## Understanding Template Container Behavior

### Template container runs for 1 minute then stops

This is expected behavior. Template containers are designed to run briefly to:

- Register with Azure DevOps
- Establish agent capabilities for KEDA
- Provide scaling reference information
- Then stop after 1 minute

The template agent will remain in your Azure DevOps agent pool as "offline" - this is normal and required for KEDA to function properly.

### "No deploy tasks available" error on first run

This error typically occurs when:

- The template container starts before any pipeline jobs are queued
- KEDA has not yet scaled up regular worker agents
- The system is operating normally during the initial deployment phase

**Solution**: This is expected behavior during deployment. The template container will stop after 1 minute, and KEDA will scale up regular agents when actual jobs are queued.

### Template agent appears in Azure DevOps but shows as offline

This is normal behavior. The template agent:

- Registers with Azure DevOps to provide capability information
- Runs for 1 minute then stops (showing as "offline")
- Remains in the pool as a reference for KEDA scaling decisions
- Should not be manually removed from the pool

## Agents restart every minute when auto-scaling is disabled

With `autoscaling.enabled: false`, the chart deploys long-lived agents through a Deployment. In Blue Agent 10.0.0 to 12.0.1, those agents were removed from the pool after 60 seconds without a job, then the container exited with `An error occurred: Not configured` and restarted in a loop.

The idle timeout is meant for auto-scaled agents only, where a pod is started for a queued job and should be cleaned up quickly if nothing picks it up. It is now disabled on the Deployment: agents stay registered until they receive a job, then restart with a fresh workspace.

If you run the container outside of the Helm chart, set the environment variable `AZP_IDLE_TIMEOUT=0` for long-lived agents. Any other value is the number of seconds to wait for a job before the agent is removed (default `60`).

## Pods are stuck with `FailedMount` or `unbound immediate PersistentVolumeClaims`

The work directory and the system temporary directory are [generic ephemeral volumes](https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/#generic-ephemeral-volumes), created from `pipelines.cache.type` and `pipelines.tmpdir.type` (the cluster default StorageClass when empty).

- `pod has unbound immediate PersistentVolumeClaims`: the StorageClass does not exist, or there is no default StorageClass. Check with `kubectl get storageclass` and set `pipelines.cache.type` and `pipelines.tmpdir.type`.
- `no Pending workload pods for volume ... to be mounted`: this is a [Longhorn issue](https://github.com/longhorn/longhorn/issues/8072) with ephemeral volumes, fixed in Longhorn 1.6.1.
- Any other storage that does not support ephemeral volumes: set `pipelines.cache.volumeEnabled` and `pipelines.tmpdir.volumeEnabled` to `false` to use an `emptyDir`, and raise `resources.limits.ephemeral-storage`.

## Pods are evicted by Kubernetes with the message `Pod ephemeral local storage usage exceeds the total limit of containers`

This error is due to the fact that the default ephemeral storage limit is set to a lower value than the one used by the pipeline. You can fix it by setting the value to more than default value in `resources.limits.ephemeral-storage`.

This error notably happens when using BuildKit with an `emptyDir` and a large number of layers.

```yaml
# values.yaml (extract)
resources:
  limits:
    ephemeral-storage: 16Gi
```

## Pods are started but never selected by Azure DevOps when using multiple architectures

Prefer hardcoding the architecture in both the pipeline and the Helm values. As this, KEDA will be able to select the right pods matching the architecture. Otherwise, there is a possibility that the deployment selected by KEDA is not matching the requested architecture.

```yaml
# azure-pipelines.yaml (extract)
stages:
  - stage: test
    jobs:
      - job: test
        pool:
          demands:
            - arch_x64
```

```yaml
# values.yaml (extract)
extraNodeSelectors:
  kubernetes.io/arch: arm64

pipelines:
  capabilities:
    - arch_arm64
```

## Container fails to a `ContainerStatusUnknown` state

Error is often due to two things:

- Kubernetes is not able to pull the image: check the image name and the credentials, if you are using the public registry, mind the domain whitelist
- Pod has been ecivted by Kubernetes due to the excessive local storage usage: parameter `ephemeral-storage` in `resources` Helm values is set to `8Gi` by default, you can increase it to `16Gi` for example

## Namespaces must be set to a non-zero value

This error is due to the fact that BuildKit needs to create a new user namespace, and the default maximum number of namespaces is 0. Value is defined by `user.max_user_namespaces` ([documentation](https://man7.org/linux/man-pages/man7/namespaces.7.html)). You can fix it by setting the value to more than 1000. Issue notably happens on AWS Bottlerocket OS. [See the related issue in the original project.](https://github.com/clemlesne/blue-agent/issues/19)

We can update dynamically the host system settings with a DaemonSet:

```yaml
# daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app.kubernetes.io/component: sysctl
    app.kubernetes.io/name: sysctl-max-user-ns-fix
    app.kubernetes.io/part-of: blue-agent
  name: sysctl-max-user-ns-fix
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: sysctl-max-user-ns-fix
  template:
    metadata:
      labels:
        app.kubernetes.io/name: sysctl-max-user-ns-fix
    spec:
      containers:
        - name: sysctl-max-user-ns-fix
          image: docker.io/library/busybox:1.36
          command:
            [
              "sh",
              "-euxc",
              "sysctl -w user.max_user_namespaces=63359 && sleep infinity",
            ]
          securityContext:
            privileged: true
```

## Change Buildkit working directory

If need Buildkit to write in another folder, then create the buildkitd.toml file and set the root variable. Example below (bash in the pipeline):

```bash
mkdir ~/.config/buildkit
echo 'root = "/app-root/.local/tmp/buildkit"' > ~/.config/buildkit/buildkitd.toml
```

## The agent has exceeded the 60-minute time limit

If the pipeline takes longer than 60 minutes, you need to change two things.

1. The technical pipeline timeout with `pipelines.timeout` Helm value to 7200 seconds (2 hours) for example.
2. Increase the functional pipeline timeout in Azure DevOps. Go to `Options > Build job > Build job timeout in minutes`.

{{< callout type="info" >}}
Set a technical pipeline timeout longer than the functional pipeline timeout to avoid the system to kill the pipeline abruptly.
{{< /callout >}}

![Configuration in the web interface.](build-job-timeout-in-minutes.png)

## A task fails with `This step requires a node version that does not exist in the agent filesystem`

The task only declares an end-of-life Node.js handler (6, 10 or 16), which Linux images no longer ship, including the `alpine` flavor. Upgrade the task to a recent major version, or force the Node.js 24 runner with the `AGENT_USE_NODE24: true` pipeline variable. See [Node.js task runners](../advanced-topics/provided-software#linux-nodejs-task-runners).

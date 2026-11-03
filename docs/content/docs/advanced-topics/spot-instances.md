---
title: Spot instances
---

Spot instances (AWS) and Spot VMs (Azure) cost 60 to 90% less than on-demand capacity, and fit build agents well: agents are stateless and short-lived. The trade-off is that the cloud provider can reclaim a node at any time, with a short notice (2 minutes on AWS, 30 seconds on Azure).

{{< callout type="warning" >}}
When a node is reclaimed, the running job fails with a message like "We stopped hearing from agent". Azure Pipelines does not retry it automatically, developers have to re-run the job, and cannot always tell an infrastructure interruption from a pipeline error. Keep critical jobs (releases, deployments) on on-demand capacity.
{{< /callout >}}

The chart exposes the standard scheduling settings, applied to the auto-scaled Jobs, the template Pod, and the Deployment: `extraNodeSelectors`, `tolerations`, `affinity`, `topologySpreadConstraints`, and `priorityClassName`.

#### Amazon EKS with Karpenter

Create a NodePool allowing both spot and on-demand capacity. When both are allowed, Karpenter launches spot instances first, from the cheapest and most available pools, and falls back to on-demand when no spot capacity is available. Enable [interruption handling](https://karpenter.sh/docs/concepts/disruption/#interruption) so Karpenter drains the node as soon as the interruption notice is received.

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: azure-pipelines
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      taints:
        - key: azure-pipelines
          effect: NoSchedule
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
```

```yaml
# values.yaml (extract)
extraNodeSelectors:
  karpenter.sh/nodepool: azure-pipelines
tolerations:
  - key: azure-pipelines
    operator: Exists
    effect: NoSchedule
annotations:
  # Do not move a running agent to consolidate nodes, a voluntary disruption would fail the job
  # Spot interruptions are not voluntary, they still apply
  karpenter.sh/do-not-disrupt: "true"
```

To force spot capacity for a given Helm instance (and accept that jobs wait in the queue when no spot capacity is available), add `karpenter.sh/capacity-type: spot` to `extraNodeSelectors`.

#### Azure Kubernetes Service with Spot node pools

Create a Spot node pool with the cluster autoscaler, scaling to zero when not used:

```bash
az aks nodepool add \
  --resource-group my-rg \
  --cluster-name my-aks \
  --name spotagents \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 20
```

AKS adds the label and the taint `kubernetes.azure.com/scalesetpriority=spot` to Spot nodes. Tolerate the taint, and prefer Spot nodes so agents can still run on regular nodes:

```yaml
# values.yaml (extract)
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: kubernetes.azure.com/scalesetpriority
              operator: In
              values: ["spot"]
```

A preference only applies to existing nodes: to make the cluster autoscaler add Spot nodes first, use the [priority expander](https://learn.microsoft.com/en-us/azure/aks/cluster-autoscaler#use-the-cluster-autoscaler-profile) with a higher priority for the Spot node pool. To only run on Spot nodes, replace the preference by `extraNodeSelectors: { kubernetes.azure.com/scalesetpriority: spot }`.

#### Mixing spot and on-demand agents

Deploy two Helm instances with distinct [capabilities](../capabilities), one scheduled on spot capacity and one on on-demand capacity, and let pipelines demand the on-demand agents for critical jobs.

Other settings worth tuning:

- `topologySpreadConstraints`: spread agents across zones, so a capacity shortage in one zone does not stop all builds.
- `priorityClassName`: a low priority class lets the scheduler preempt idle agents first when the cluster is full, a high one protects running builds from other workloads.
- `pipelines.cache` and `pipelines.tmpdir`: zonal block volumes are created with the Pod, use a StorageClass with `volumeBindingMode: WaitForFirstConsumer`.

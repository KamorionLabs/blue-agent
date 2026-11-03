---
title: Scaling
---

With [KEDA](https://keda.sh) installed in the cluster and `autoscaling.enabled: true` (default), agents are created on demand and scale to zero. Without KEDA, or with `autoscaling.enabled: false`, the chart deploys a fixed number of long-lived agents (`replicaCount`) in a Deployment.

#### How auto-scaling works

- At each Helm release, a template Pod registers an agent named `<release>-template` for one minute, then stops. It stays offline in the pool: KEDA uses its capabilities to know which queued jobs this release can run (`parent` of the [Azure Pipelines scaler](https://keda.sh/docs/latest/scalers/azure-pipelines/)). Do not remove it from the pool.
- Every `autoscaling.pollingInterval` seconds, KEDA reads the queue of the pool and creates one Kubernetes Job per pipeline job, up to `autoscaling.maxReplicas`. A low interval starts agents faster, but increases the load on the Azure DevOps API, which is rate limited.
- Each Job runs one agent with `--once`: it registers, runs one pipeline job, unregisters, and exits. Workspaces are never shared between pipeline jobs.
- An agent that receives no job within `autoscaling.idleTimeout` seconds (default 60) unregisters and exits. This cleans up agents created for a job that another agent picked up first.
- Jobs are stopped after `pipelines.timeout` seconds (default 1 hour), and their history is kept according to `pipelines.cleanup`.

Agents start in the time needed to schedule the Pod, provision its volumes (see `pipelines.cache` and `pipelines.tmpdir`), pull the image, and register: from a few seconds on a warm node, to a few minutes when a node has to be added to the cluster.

#### Scaling strategy and KEDA versions

The Azure Pipelines scaler changed how it counts jobs already assigned to an agent ("in-flight" jobs), and the KEDA [scaling strategy](https://keda.sh/docs/latest/reference/scaledjob-spec/#scalingstrategy) must match:

| KEDA version | In-flight jobs counted       | Recommended values                                                                            |
| ------------ | ---------------------------- | --------------------------------------------------------------------------------------------- |
| <= 2.19      | Always                       | `scalingStrategy: accurate` (extra agents expire after the idle timeout)                      |
| 2.20         | Never                        | `scalingStrategy: accurate`                                                                   |
| >= 2.21      | Depends on `scaleOnInFlight` | `accurate` with `scaleOnInFlight: false` (default), or `default` with `scaleOnInFlight: true` |

The chart defaults (`accurate`, `scaleOnInFlight: false`) work for all versions. The `default` strategy is required to keep warm agents on a schedule (see below).

#### Warm agents

`autoscaling.minReplicas` keeps a minimum number of agents running, even with an empty queue, so the first jobs do not wait for a Pod to start. As agents run one job and exit, KEDA starts a new one each time a warm agent is used. Idle warm agents are also recycled after `autoscaling.idleTimeout`: raise it (for example to `1800`, below `pipelines.timeout`) to limit the churn of Pods and volumes.

Warm agents are billed all the time. To keep them only during business hours, and scale to zero at night and on weekends, use `autoscaling.schedules`. Each schedule is rendered as a KEDA [cron trigger](https://keda.sh/docs/latest/scalers/cron/), combined with the Azure Pipelines trigger with `multipleScalersCalculation: max`: during the window, the number of agents is the highest of the schedule and of the queue.

```yaml
# values.yaml (extract)
autoscaling:
  minReplicas: 0
  # Required with schedules, KEDA >= 2.21
  scalingStrategy: default
  scaleOnInFlight: true
  multipleScalersCalculation: max
  # Recycle idle warm agents every 30 minutes
  idleTimeout: 1800
  schedules:
    # 2 warm agents on weekdays, from 8:00 to 19:00 Paris time
    - timezone: Europe/Paris
      start: "0 8 * * 1-5"
      end: "0 19 * * 1-5"
      desiredReplicas: 2
```

With this configuration:

- On weekdays from 8:00 to 19:00, 2 agents wait for jobs. When more jobs are queued than idle agents, KEDA adds agents up to `autoscaling.maxReplicas`.
- At night and on weekends, the cron trigger is inactive and agents only start for queued jobs, then scale back to zero.

{{< callout type="warning" >}}
The chart refuses schedules with the `accurate` strategy: this strategy only subtracts pending Jobs from the target, so KEDA would create new agents at every polling interval while warm agents are idle. With the `default` strategy, KEDA subtracts all running agents, which requires the scaler to count in-flight jobs (`scaleOnInFlight: true`, KEDA >= 2.21). If other agents outside this Helm release serve the same pool and capabilities, their in-flight jobs are counted too, and KEDA may start a few extra agents, which expire after the idle timeout.
{{< /callout >}}

#### Custom triggers

`autoscaling.extraTriggers` adds any [KEDA trigger](https://keda.sh/docs/latest/scalers/) to the ScaledJob, for example a cron trigger with options not covered by `autoscaling.schedules`. Values are templated:

```yaml
# values.yaml (extract)
autoscaling:
  extraTriggers:
    - type: cron
      name: "{{ .Release.Name }}-release-day"
      metadata:
        timezone: Europe/Paris
        start: "0 6 1 * *"
        end: "0 22 1 * *"
        desiredReplicas: "10"
```

The same strategy constraints apply as for `autoscaling.schedules`.

#### Without auto-scaling

With `autoscaling.enabled: false`, `replicaCount` agents run in a Deployment. They have no idle timeout: each agent waits for a job, runs it, exits, and is restarted by Kubernetes with a clean workspace. A Helm upgrade restarts the agents, waiting for running jobs up to `pipelines.timeout`.

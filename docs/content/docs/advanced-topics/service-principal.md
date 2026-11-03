---
title: Service principal
---

By default, agents register in the pool with a Personal Access Token (PAT), which is tied to a user and expires. Agents can instead register with a [Microsoft Entra service principal](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/service-principal-agent-registration?view=azure-devops), supported from Azure Pipelines agent 3.227.1.

#### What is supported

| Component                                    | PAT           | Service principal (client secret) | Workload identity                           |
| -------------------------------------------- | ------------- | --------------------------------- | ------------------------------------------- |
| Agent registration (`pipelines.auth.type`)   | Yes (default) | Yes                               | No, the agent only supports a client secret |
| KEDA queue polling (`autoscaling.auth.type`) | Yes           | Yes, KEDA >= 2.21                 | Yes, identity of the KEDA operator          |

The client secret is only used to register and remove the agent: it is passed to the agent configuration through the environment, and removed from the environment of the jobs. KEDA and the agents can use different authentications, for example a service principal for the agents and a read-only PAT, or the KEDA operator identity, for the queue.

`secret.azureKeyVault` only supports the PAT authentication.

#### Prerequisites

1. Create an app registration in Microsoft Entra ID, with a client secret.
2. Add the service principal to the Azure DevOps organization (_Organization settings_ > _Users_), with the _Basic_ access level.
3. Grant it the _Administrator_ role on the agent pool (_Organization settings_ > _Agent pools_ > pool > _Security_).

#### Configuration

```yaml
# values.yaml (extract)
pipelines:
  organizationURL: https://dev.azure.com/my-org
  poolName: my-pool
  auth:
    type: servicePrincipal
    clientId: MY_CLIENT_ID
    tenantId: MY_TENANT_ID
    clientSecret: MY_CLIENT_SECRET
```

With `secret.create: false`, the Secret must contain the keys `organizationURL` and `clientSecret` (plus `personalAccessToken` if KEDA uses a PAT).

KEDA uses the same service principal by default, which requires KEDA 2.21 or later. With an older KEDA, keep a PAT for KEDA only (scope _Agent Pools (Read)_):

```yaml
# values.yaml (extract)
pipelines:
  personalAccessToken: MY_READ_ONLY_PAT
autoscaling:
  auth:
    type: pat
```

Or use the [workload identity of the KEDA operator](https://keda.sh/docs/latest/authentication-providers/azure-ad-workload-identity/). The identity must be added to the Azure DevOps organization, with the _Reader_ role on the agent pool:

```yaml
# values.yaml (extract)
autoscaling:
  auth:
    type: workloadIdentity
    # Optional, client ID of the identity if the KEDA operator has several
    identityId: MY_IDENTITY_CLIENT_ID
```

#### Container environment variables

Outside of the Helm chart, set `AZP_AUTH=SP`, `AZP_CLIENT_ID`, `AZP_TENANT_ID` and `AZP_CLIENT_SECRET` (or `AZP_CLIENT_SECRET_FILE`, a file containing it) instead of `AZP_TOKEN`.

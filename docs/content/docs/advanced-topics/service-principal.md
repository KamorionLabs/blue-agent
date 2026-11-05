---
title: Service principal and workload identity
---

By default, agents register in the pool with a Personal Access Token (PAT), which is tied to a user and expires. Agents can instead register with a [Microsoft Entra service principal](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/service-principal-agent-registration?view=azure-devops), supported from Azure Pipelines agent 3.227.1, or with a [Microsoft Entra Workload ID](https://azure.github.io/azure-workload-identity/docs/), without any secret.

#### What is supported

| Component                                    | PAT           | Service principal (client secret) | Workload identity                           |
| -------------------------------------------- | ------------- | --------------------------------- | ------------------------------------------- |
| Agent registration (`pipelines.auth.type`)   | Yes (default) | Yes                               | Yes, no secret                              |
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

#### Workload identity

The agent exchanges the service account token projected by the [Azure Workload Identity webhook](https://azure.github.io/azure-workload-identity/docs/installation.html) for a Microsoft Entra access token, and registers with it in place of a PAT. A new token is requested to register and to remove the agent. It works on any Kubernetes cluster running the webhook, AKS or not (EKS, GKE, on-premises), as long as Microsoft Entra ID trusts the OIDC issuer of the cluster.

1. Install the Azure Workload Identity webhook on the cluster.
2. Create an app registration (or a user-assigned managed identity) in Microsoft Entra ID, with a federated credential: issuer is the OIDC issuer URL of the cluster, subject is `system:serviceaccount:<namespace>:<service account of the release>`.
3. Add it to the Azure DevOps organization, with the _Basic_ access level, and grant it the _Administrator_ role on the agent pool.
4. For KEDA, add a second federated credential for the KEDA operator service account (`system:serviceaccount:<keda namespace>:keda-operator`), and enable `podIdentity.azureWorkload` in the KEDA Helm chart.

```yaml
# values.yaml (extract)
pipelines:
  organizationURL: https://dev.azure.com/my-org
  poolName: my-pool
  auth:
    type: workloadIdentity
    clientId: MY_CLIENT_ID
    # Optional, defaults to the tenant configured in the webhook
    tenantId: MY_TENANT_ID
```

The chart annotates the service account with the client ID, labels the agent pods with `azure.workload.identity/use: "true"`, and KEDA follows with its operator identity (`autoscaling.auth.type: workloadIdentity`, `identityId` defaulting to `pipelines.auth.clientId`). The Secret only holds `organizationURL`.

The token file stays readable by the jobs run by the agent, like the cluster credentials of any pod: grant the identity nothing more than the agent pool role.

#### Container environment variables

Outside of the Helm chart, set `AZP_AUTH=SP`, `AZP_CLIENT_ID`, `AZP_TENANT_ID` and `AZP_CLIENT_SECRET` (or `AZP_CLIENT_SECRET_FILE`, a file containing it) instead of `AZP_TOKEN`. For a workload identity, set `AZP_AUTH=WI` and let the webhook inject `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE` and `AZURE_AUTHORITY_HOST`.

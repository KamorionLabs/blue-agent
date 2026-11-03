---
title: 0 trust
---

By design, Blue Agent must be able to use a token to register itself to the Azure DevOps server. Centrally manage the tokens storage, their lifecycle and their access [greatly improve operational security](https://en.wikipedia.org/wiki/Zero_trust_architecture).

#### Kubernetes (Helm)

##### Azure Kubernetes Service

The organization URL and the PAT can be stored in Azure Key Vault instead of a Kubernetes `Secret`:

- Agents read them from the files mounted by the [Secrets Store CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) (`AZP_URL_FILE` and `AZP_TOKEN_FILE`). They do not depend on a synchronized Kubernetes `Secret`, which only exists while a Pod mounts the volume.
- KEDA reads them directly from Key Vault with its [Azure Key Vault authentication provider](https://keda.sh/docs/latest/authentication-providers/azure-key-vault/), so it can scale from zero.

Prerequisites to the deployment are:

- The Key Vault provider for Secrets Store CSI Driver add-on [installed in the cluster](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver).
- A Key Vault with two secrets named `organization-url` and `personal-access-token`, both of type `secret`.
- A user-assigned Managed Identity with the `Key Vault Secrets User` role on the Key Vault.
- [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) enabled on the cluster, with federated credentials on the Managed Identity for the agent service account (`system:serviceaccount:<namespace>:<release>`) and for the KEDA operator service account (by default `system:serviceaccount:keda:keda-operator`). KEDA must run with [workload identity](https://keda.sh/docs/latest/authentication-providers/azure-ad-workload-identity/) enabled.

```yaml
# values.yaml
secret:
  create: true
  azureKeyVault:
    enabled: true
    managedIdentityId: MY_MANAGED_IDENTITY_CLIENT_ID
    name: MY_KEY_VAULT_NAME
    tenantId: MY_TENANT_ID
serviceAccount:
  annotations:
    azure.workload.identity/client-id: MY_MANAGED_IDENTITY_CLIENT_ID
```

To let the CSI driver use the node (VM) managed identity instead of Workload ID, set `secret.azureKeyVault.useVMManagedIdentity: true`; `managedIdentityId` is then the client ID of the user-assigned identity attached to the nodes. KEDA still authenticates with Workload ID, with the same `managedIdentityId`.

##### Other distributions

Disable the secret creation in the Helm chart, and integrate yourself with your own secret management solution.

```yaml
# values.yaml
secret:
  create: false
```

#### Azure Container Apps (Bicep)

Bicep is not supported out of the box. But, integration between Azure Key Vault and Azure Container Apps is native and can be done in an hour. [See the documentation.](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets?tabs=azure-cli)

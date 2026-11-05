# Start the Azure DevOps agent in a Windows container
#
# This script handles both regular agent execution and template container creation.
# Template containers are special agents that serve as references for KEDA auto-scaling.
#
# Template Container Logic:
# - When AZP_TEMPLATE_JOB=1, the agent runs as a template container
# - Template containers register with Azure DevOps but don't process jobs
# - They run for 1 minute to establish capabilities, then stop
# - KEDA uses the template agent as a reference for scaling decisions
# - This prevents scaling errors when no agents are initially available
#
# Agent is always registered. It is removed from the server only when the agent is not a template job. After AZP_IDLE_TIMEOUT secs without a job (default 60), it tries to shut down the agent gracefully, waiting for the current job to finish, if any. Long-lived agents (Helm chart with auto-scaling disabled) set AZP_IDLE_TIMEOUT=0 to stay registered until they receive a job.
#
# Environment variables:
# - AZP_AGENT_NAME: Agent name (default: hostname)
# - AZP_AUTH: Authentication used to register the agent, "PAT", "SP" for a Microsoft Entra service principal or "WI" for Microsoft Entra Workload ID (default: PAT)
# - AZURE_AUTHORITY_HOST, AZURE_CLIENT_ID, AZURE_FEDERATED_TOKEN_FILE, AZURE_TENANT_ID: Workload identity, injected by the Azure Workload Identity webhook (AZP_AUTH=WI)
# - AZP_CLIENT_ID: Service principal client ID (AZP_AUTH=SP)
# - AZP_CLIENT_SECRET: Service principal client secret (AZP_AUTH=SP)
# - AZP_CLIENT_SECRET_FILE: File containing the service principal client secret, used when AZP_CLIENT_SECRET is not set (default: empty)
# - AZP_CUSTOM_CERT_PEM: Custom SSL certificates directory (default: empty)
# - AZP_IDLE_TIMEOUT: Seconds to wait for a job before removing an idle agent (default: 60) - 0 disables the idle timeout
# - AZP_POOL: Agent pool name
# - AZP_TEMPLATE_JOB: Template job flag (default: 0) - when set to 1, creates template container
# - AZP_TENANT_ID: Service principal tenant ID (AZP_AUTH=SP)
# - AZP_TOKEN: Personal access token (AZP_AUTH=PAT)
# - AZP_TOKEN_FILE: File containing the personal access token, used when AZP_TOKEN is not set (default: empty)
# - AZP_URL: Server URL
# - AZP_URL_FILE: File containing the server URL, used when AZP_URL is not set (default: empty)
# - AZP_WORK: Work directory

##
# Misc functions
##

function Write-Header() {
  Write-Host "➡️ $1" -ForegroundColor Cyan
}

function Write-Warning() {
  Write-Host "⚠️ $1" -ForegroundColor Yellow
}

function Raise-Error() {
  throw "❌ $1"
}

##
# Argument parsing
##

# Read a variable from the file named by "<name>_FILE" when the variable itself is empty
# Used with files mounted by the Secrets Store CSI Driver, which do not depend on a synchronized Kubernetes Secret
foreach ($name in @("AZP_URL", "AZP_TOKEN", "AZP_CLIENT_SECRET")) {
  $value = [Environment]::GetEnvironmentVariable($name)
  $file = [Environment]::GetEnvironmentVariable("${name}_FILE")
  if (($null -eq $value -or $value -eq "") -and ($null -ne $file -and $file -ne "")) {
    if (!(Test-Path $file)) {
      Raise-Error "File $file from ${name}_FILE environment variable is not readable"
    }
    [Environment]::SetEnvironmentVariable($name, (Get-Content -Raw $file).Trim())
  }
}

if ($null -eq $Env:AZP_URL -or $Env:AZP_URL -eq "") {
  Raise-Error "Missing AZP_URL environment variable"
}

$azpAuth = if ($null -eq $Env:AZP_AUTH -or $Env:AZP_AUTH -eq "") { "PAT" } else { $Env:AZP_AUTH.ToUpper() }
$clientSecret = $null
if ($azpAuth -eq "PAT") {
  if ($null -eq $Env:AZP_TOKEN -or $Env:AZP_TOKEN -eq "") {
    Raise-Error "Missing AZP_TOKEN environment variable"
  }
  $authArgs = @("--auth", "PAT", "--token", $Env:AZP_TOKEN)
  # The agent and the jobs it runs inherit this environment, the token is only needed to configure and remove the agent
  Remove-Item Env:AZP_TOKEN
} elseif ($azpAuth -eq "SP") {
  foreach ($name in @("AZP_CLIENT_ID", "AZP_CLIENT_SECRET", "AZP_TENANT_ID")) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($null -eq $value -or $value -eq "") {
      Raise-Error "Missing $name environment variable, required with AZP_AUTH=SP"
    }
  }
  # The client secret is passed through the environment, not the command line, and only to the configuration commands
  $authArgs = @("--auth", "SP", "--clientid", $Env:AZP_CLIENT_ID, "--tenantid", $Env:AZP_TENANT_ID)
  $clientSecret = $Env:AZP_CLIENT_SECRET
  Remove-Item Env:AZP_CLIENT_SECRET
} elseif ($azpAuth -eq "WI") {
  foreach ($name in @("AZURE_AUTHORITY_HOST", "AZURE_CLIENT_ID", "AZURE_FEDERATED_TOKEN_FILE", "AZURE_TENANT_ID")) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($null -eq $value -or $value -eq "") {
      Raise-Error "Missing $name environment variable, required with AZP_AUTH=WI (is the pod labeled for the Azure Workload Identity webhook?)"
    }
  }
  # Azure DevOps accepts a Microsoft Entra access token in place of a personal access token
  $authArgs = @("--auth", "PAT")
} else {
  Raise-Error "Unsupported AZP_AUTH value ($Env:AZP_AUTH), use PAT, SP or WI"
}

# Exchange the federated token of the workload identity for a Microsoft Entra access token to Azure DevOps
# The projected token is refreshed by the kubelet, so a new access token is requested for each configuration command
function Get-WorkloadIdentityToken {
  $body = @{
    client_id             = $Env:AZURE_CLIENT_ID
    scope                 = "499b84ac-1321-427f-aa17-267ca6975798/.default"
    grant_type            = "client_credentials"
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    client_assertion      = (Get-Content -Raw $Env:AZURE_FEDERATED_TOKEN_FILE).Trim()
  }
  $uri = "$($Env:AZURE_AUTHORITY_HOST.TrimEnd('/'))/$($Env:AZURE_TENANT_ID)/oauth2/v2.0/token"
  try {
    return (Invoke-RestMethod -Method Post -Uri $uri -Body $body -MaximumRetryCount 3).access_token
  } catch {
    Raise-Error "Failed to get a Microsoft Entra access token with the workload identity $($Env:AZURE_CLIENT_ID): $($_.Exception.Message)"
  }
}

# Run the agent configuration script with the authentication arguments
function Invoke-Config {
  if ($azpAuth -eq "WI") {
    $Env:VSTS_AGENT_INPUT_TOKEN = Get-WorkloadIdentityToken
  } elseif ($null -ne $clientSecret) {
    $Env:VSTS_AGENT_INPUT_CLIENTSECRET = $clientSecret
  }
  try {
    & config.cmd @Args @authArgs
  } finally {
    Remove-Item Env:VSTS_AGENT_INPUT_CLIENTSECRET -ErrorAction SilentlyContinue
    Remove-Item Env:VSTS_AGENT_INPUT_TOKEN -ErrorAction SilentlyContinue
  }
}

if ($null -eq $Env:AZP_POOL -or $Env:AZP_POOL -eq "") {
  Raise-Error "Missing AZP_POOL environment variable"
}

# If name is not set, use the hostname
if ($null -eq $Env:AZP_AGENT_NAME -or $Env:AZP_AGENT_NAME -eq "") {
  Write-Warning "Missing AZP_AGENT_NAME environment variable, using hostname"
  $Env:AZP_AGENT_NAME = $Env:COMPUTERNAME
}

if ($null -eq $Env:AZP_WORK -or $Env:AZP_WORK -eq "") {
  Raise-Error "Missing AZP_WORK environment variable"
}

if (!(Test-Path $Env:AZP_WORK)) {
  Write-Warning "Work dir AZP_WORK ($Env:AZP_WORK) does not exist, creating it, but reliability is not guaranteed"
  New-Item -Path $Env:AZP_WORK -ItemType Directory
}

$isTemplateJob = $false
if ($Env:AZP_TEMPLATE_JOB -eq "1") {
  Write-Warning "Template job enabled, agent cannot be used for running jobs - see documentation for details"
  $isTemplateJob = $true
  $Env:AZP_AGENT_NAME = "$Env:AZP_AGENT_NAME-template"
}

Write-Header "Running agent $Env:AZP_AGENT_NAME in pool $Env:AZP_POOL"

##
# Cleanup function
##

function Unregister {
  Write-Header "Removing agent"

  # If the agent has some running jobs, the configuration removal process will fail; so, give it some time to finish the job
  while ($true) {
    try {
      # If the agent is removed successfully, exit the loop
      Invoke-Config remove `
        --unattended
      break
    } catch {
      Write-Host "A job is still running, waiting 15 seconds before retrying the removal"
      Start-Sleep -Seconds 15
    }
  }
}

##
# Custom SSL certificates
##

Write-Header "Adding custom SSL certificates"

if ((Test-Path $Env:AZP_CUSTOM_CERT_PEM) -and ((Get-ChildItem $Env:AZP_CUSTOM_CERT_PEM).Count -gt 0)) {
  Write-Host "Searching for *.crt in $Env:AZP_CUSTOM_CERT_PEM"

  Get-ChildItem $Env:AZP_CUSTOM_CERT_PEM -Filter *.crt | ForEach-Object {
    Write-Host "Certificate $($_.Name)"

    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($_.FullName)
    Write-Host "  Valid from: " $cert.NotBefore
    Write-Host "  Valid to:   " $cert.NotAfter

    Write-Host "Updating certificates keychain"
    Import-Certificate -FilePath $_.FullName -CertStoreLocation Cert:\LocalMachine\Root
  }
} else {
  Write-Host "No custom SSL certificate provided"
}

##
# Agent configuration
##

Write-Header "Configuring agent"

Set-Location $(Split-Path -Parent $MyInvocation.MyCommand.Definition)

Invoke-Config `
  --acceptTeeEula `
  --agent $Env:AZP_AGENT_NAME `
  --gitUseSChannel `
  --pool $Env:AZP_POOL `
  --replace `
  --unattended `
  --url $Env:AZP_URL `
  --work $Env:AZP_WORK

##
# Agent execution
##

Write-Header "Running agent"

# Running it with the --once flag at the end will shut down the agent after the build is executed
if ($isTemplateJob) {
  Write-Host "Agent will be stopped after 1 min"
  # Run the agent for a minute to allow registration and capability detection
  Start-Job -ScriptBlock {
    Start-Sleep -Seconds 60
    & run.cmd $Args --once
  }
} else {
  try {
    # Run the countdown for fast-clean if no job is using the agent after a delay
    # Disabled (0) for long-lived agents, e.g. when deployed without auto-scaling, otherwise the agent would be removed after the delay and the container would restart in a loop (see #361)
    $idleTimeout = 60
    if ($Env:AZP_IDLE_TIMEOUT) {
      if ($Env:AZP_IDLE_TIMEOUT -match '^[0-9]+$') {
        $idleTimeout = [int]$Env:AZP_IDLE_TIMEOUT
      } else {
        Write-Warning "Invalid AZP_IDLE_TIMEOUT value ($Env:AZP_IDLE_TIMEOUT), using the default of 60 seconds"
      }
    }
    if ($idleTimeout -gt 0) {
      Write-Host "Agent will be removed if no job is received within $idleTimeout seconds"
      Start-Job -ScriptBlock {
        Start-Sleep -Seconds $using:idleTimeout
        Unregister
      }
    } else {
      Write-Host "Idle timeout disabled, agent stays registered until it receives a job"
    }
    # Run the agent
    & run.cmd $Args --once
  } finally {
    # Unregister on success, Ctrl+C, and SIGTERM
    Unregister
  }
}

##
# Diagnostics
##

Write-Header "Printing agent diag logs"

Get-Content $AGENT_DIAGLOGPATH/*.log

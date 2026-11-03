#!/bin/bash
set -e

# Start the Azure DevOps agent in a Linux container
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
# - AZP_AUTH: Authentication used to register the agent, "PAT" or "SP" for a Microsoft Entra service principal (default: PAT)
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

write_header() {
  lightcyan='\033[1;36m'
  nocolor='\033[0m'
  echo -e "${lightcyan}➡️ $1${nocolor}"
}

write_warning() {
  yellow='\033[1;33m'
  nocolor='\033[0m'
  echo -e "${yellow}⚠️ $1${nocolor}"
}

raise_error() {
  red='\033[1;31m'
  nocolor='\033[0m'
  echo 1>&2 -e "${red}❌ $1${nocolor}"
}

##
# Argument parsing
##

# Read a variable from the file named by "<name>_FILE" when the variable itself is empty
# Used with files mounted by the Secrets Store CSI Driver, which do not depend on a synchronized Kubernetes Secret
read_from_file() {
  local name=$1
  local file_name="${1}_FILE"
  if [ -z "${!name}" ] && [ -n "${!file_name}" ]; then
    if [ ! -r "${!file_name}" ]; then
      raise_error "File ${!file_name} from ${file_name} environment variable is not readable"
      exit 1
    fi
    printf -v "$name" '%s' "$(tr -d '\r\n' < "${!file_name}")"
  fi
}

read_from_file AZP_URL
read_from_file AZP_TOKEN
read_from_file AZP_CLIENT_SECRET

if [ -z "$AZP_URL" ]; then
  raise_error "Missing AZP_URL environment variable"
  exit 1
fi

AZP_AUTH="${AZP_AUTH:-PAT}"
client_secret=""
case "${AZP_AUTH^^}" in
  PAT)
    if [ -z "$AZP_TOKEN" ]; then
      raise_error "Missing AZP_TOKEN environment variable"
      exit 1
    fi
    auth_args=(--auth PAT --token "$AZP_TOKEN")
    # The agent and the jobs it runs inherit this environment, the token is only needed to configure and remove the agent
    unset AZP_TOKEN
    ;;
  SP)
    for name in AZP_CLIENT_ID AZP_CLIENT_SECRET AZP_TENANT_ID; do
      if [ -z "${!name}" ]; then
        raise_error "Missing $name environment variable, required with AZP_AUTH=SP"
        exit 1
      fi
    done
    # The client secret is passed through the environment, not the command line, and only to the configuration commands
    auth_args=(--auth SP --clientid "$AZP_CLIENT_ID" --tenantid "$AZP_TENANT_ID")
    client_secret="$AZP_CLIENT_SECRET"
    unset AZP_CLIENT_SECRET
    ;;
  *)
    raise_error "Unsupported AZP_AUTH value (${AZP_AUTH}), use PAT or SP"
    exit 1
    ;;
esac

# Run the agent configuration script with the authentication arguments
config_agent() {
  if [ -n "$client_secret" ]; then
    VSTS_AGENT_INPUT_CLIENTSECRET="$client_secret" bash config.sh "$@" "${auth_args[@]}"
  else
    bash config.sh "$@" "${auth_args[@]}"
  fi
}

if [ -z "$AZP_POOL" ]; then
  raise_error "Missing AZP_POOL environment variable"
  exit 1
fi

# If name is not set, use the hostname
if [ -z "$AZP_AGENT_NAME" ]; then
  write_warning "Missing AZP_AGENT_NAME environment variable, using hostname"
  AZP_AGENT_NAME=$(hostname)
fi

if [ ! -w "$AZP_WORK" ]; then
  write_warning "Work dir AZP_WORK (${AZP_WORK}) does not exist, creating it, but reliability is not guaranteed"
  mkdir -p "$AZP_WORK"
fi

if [ "$AZP_TEMPLATE_JOB" == "1" ]; then
  write_warning "Template job enabled, agent cannot be used for running jobs - see documentation for details"
  is_template_job="true"
  AZP_AGENT_NAME="${AZP_AGENT_NAME}-template"
fi

write_header "Running agent $AZP_AGENT_NAME in pool $AZP_POOL"

##
# Cleanup function
##

unregister() {
  write_header "Removing agent"

  # If the agent has some running jobs, the configuration removal process will fail ; so, give it some time to finish the job
  while true; do
    # If the agent is removed successfully, exit the loop
    config_agent remove \
        --unattended \
      && break

    echo "A job is still running, waiting 15 seconds before retrying the removal"
    sleep 15
  done
}

##
# Custom SSL certificates
##

write_header "Adding custom SSL certificates"

copy_and_show() {
  local src_dir=$1
  local dest_dir=$2
  mkdir -p "$dest_dir"
  cp "$src_dir"/*.crt "$dest_dir"/
  for cert_file in "$src_dir"/*.crt; do
    echo "Adding certificate $(basename "$cert_file")"
    openssl x509 -inform PEM -in "$cert_file" -noout -issuer -subject -dates
  done
}

if [ -d "$AZP_CUSTOM_CERT_PEM" ] && [ "$(ls -A "$AZP_CUSTOM_CERT_PEM")" ]; then
  echo "Searching for *.crt in $AZP_CUSTOM_CERT_PEM"

  # Debian-family or Alpine
  if [ -f /etc/debian_version ] || [ -f /etc/alpine-release ]; then
    copy_and_show "$AZP_CUSTOM_CERT_PEM" /usr/local/share/ca-certificates
    echo "Updating certificates keychain"
    update-ca-certificates

  # RHEL-family
  elif [ -f /etc/redhat-release ]; then
    copy_and_show "$AZP_CUSTOM_CERT_PEM" /etc/ca-certificates/trust-source/anchors
    echo "Updating certificates keychain"
    update-ca-trust extract

  # Unknown distro
  else
    echo "Unrecognised distribution – manual certificate installation required" >&2
    exit 1
  fi
else
  echo "No custom SSL certificate provided"
fi

##
# Agent configuration
##

write_header "Configuring agent"

cd $(dirname "$0")

config_agent \
  --acceptTeeEula \
  --agent "$AZP_AGENT_NAME" \
  --pool "$AZP_POOL" \
  --replace \
  --unattended \
  --url "$AZP_URL" \
  --work "$AZP_WORK" &

# Fake the exit code of the agent for the prevent Kubernetes to detect the pod as failed (this is intended)
# See: https://stackoverflow.com/a/62183992/12732154
wait $!

##
# Agent execution
##

write_header "Running agent"

# Running it with the --once flag at the end will shut down the agent after the build is executed
if [ "$is_template_job" == "true" ]; then
  echo "Agent will be stopped after 1 min"
  # Run the agent for a minute to allow registration and capability detection
  timeout --preserve-status 1m bash run-docker.sh "$@" --once &
else
  # Unregister on success
  trap 'unregister; exit 0' EXIT
  # Unregister on Ctrl+C
  trap 'unregister; exit 130' INT
  # Unregister on SIGTERM
  trap 'unregister; exit 143' TERM
  # Run the countdown for fast-clean if no job is using the agent after a delay
  # Disabled (0) for long-lived agents, e.g. when deployed without auto-scaling, otherwise the agent would be removed after the delay and the container would restart in a loop (see #361)
  idle_timeout="${AZP_IDLE_TIMEOUT:-60}"
  if ! [[ "$idle_timeout" =~ ^[0-9]+$ ]]; then
    write_warning "Invalid AZP_IDLE_TIMEOUT value (${idle_timeout}), using the default of 60 seconds"
    idle_timeout=60
  fi
  if [ "$idle_timeout" -gt 0 ]; then
    echo "Agent will be removed if no job is received within ${idle_timeout} seconds"
    sleep "$idle_timeout" && unregister &
  else
    echo "Idle timeout disabled, agent stays registered until it receives a job"
  fi
  # Run the agent
  bash run-docker.sh "$@" --once &
fi

# Fake the exit code of the agent for the prevent Kubernetes to detect the pod as failed (this is intended)
# See: https://stackoverflow.com/a/62183992/12732154
wait $!

##
# Diagnostics
##

write_header "Printing agent diag logs"

cat $AGENT_DIAGLOGPATH/*.log

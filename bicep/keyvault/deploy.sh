#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Bicep Deployment Script (Improved)
# ==========================================================

# -----------------------------
# Defaults
# -----------------------------
MODE=""
ENV=""
AUTO_APPROVE=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RESOURCE_GROUP_PREFIX="rg-test"
LOCATION="westeurope"
BICEP_FILE="${SCRIPT_DIR}/main.bicep"
PARAMS_DIR="${SCRIPT_DIR}/params"


# -----------------------------
# Colors (optional but useful)
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# -----------------------------
# Logging helpers
# -----------------------------
log_info()  { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# -----------------------------
# Help
# -----------------------------
show_help() {
  cat <<EOF
Usage:
  ./create.sh --apply|--dry-run --env <env> [--yes]

Options:
  --apply           Execute deployment
  --dry-run         Preview deployment (what-if)
  --destroy         Delete the resource group and all resources
  --env <env>       Environment (e.g., dev, prod)
  --yes             Skip confirmation
  -h, --help        Show this help

Examples:
  ./create.sh --dry-run --env dev
  ./create.sh --apply --env dev --yes
EOF
}

# -----------------------------
# Parse arguments
# -----------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        MODE="apply"
        ;;
      --dry-run)
        MODE="dry-run"
        ;;
      --destroy)
        MODE="destroy" 
        ;;
      --env)
        [[ $# -lt 2 ]] && { log_error "--env requires value"; exit 1; }
        ENV="$2"
        shift
        ;;
      --yes)
        AUTO_APPROVE=true
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done

  # Validación
  if [[ -z "$MODE" || -z "$ENV" ]]; then
    log_error "Missing required parameters"
    show_help
    exit 1
  fi


}

# -----------------------------
# Pre-checks
# -----------------------------
pre_checks() {
  log_info "Running pre-checks..."

  # Check az CLI
  if ! command -v az &>/dev/null; then
    log_error "Azure CLI not installed"
    exit 1
  fi

  # Check login
  if ! az account show &>/dev/null; then
    log_error "Not logged in. Run: az login"
    exit 1
  fi
}

# -----------------------------
# Build variables
# -----------------------------

build_config() {
  RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${ENV}"
  PARAM_FILE="${PARAMS_DIR}/${ENV}.bicepparam"

  if [[ ! -f "$BICEP_FILE" ]]; then
    log_error "Bicep file not found: $BICEP_FILE"
    exit 1
  fi

  if [[ ! -f "$PARAM_FILE" ]]; then
    log_error "Params file not found: $PARAM_FILE"
    exit 1
  fi
}

# -----------------------------
# Show plan
# -----------------------------
show_plan() {
  echo "=========================================="
  echo "🚀 Deployment Plan"
  echo "=========================================="
  echo "Mode:            $MODE"
  echo "Environment:     $ENV"
  echo "Resource Group:  $RESOURCE_GROUP"
  echo "Location:        $LOCATION"
  echo "Bicep file:      $BICEP_FILE"
  echo "Params file:     $PARAM_FILE"
  echo "=========================================="
}

# -----------------------------
# Confirm
# -----------------------------
confirm() {
  if [[ "$AUTO_APPROVE" = true ]]; then
    log_warn "Auto-approve enabled"
    return
  fi

  read -r -p "Do you want to continue? (y/N): " answer
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      log_error "Aborted"
      exit 1
      ;;
  esac
}

# -----------------------------
# Ensure RG exists
# -----------------------------
ensure_rg() {
  log_info "Ensuring Resource Group exists..."

  if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    log_info "Resource Group already exists"
  else
    az group create \
      --name "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      1>/dev/null
    log_info "Resource Group created"
  fi
}

# -----------------------------
# Helper: build parameters arg
# -----------------------------
build_params_arg() {
  if [[ "$PARAM_FILE" == *.bicepparam ]]; then
    PARAM_ARG="$PARAM_FILE"
  else
    PARAM_ARG="@$PARAM_FILE"
  fi

  log_info "Using parameters: $PARAM_ARG"
}

# -----------------------------
# Dry run (what-if)
# -----------------------------
run_dry() {
  log_info "Running WHAT-IF..."

  build_params_arg

  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$BICEP_FILE" \
    --parameters "$PARAM_ARG"
}

# -----------------------------
# Apply
# -----------------------------
run_apply() {
  log_info "Applying deployment..."

  build_params_arg

  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$BICEP_FILE" \
    --parameters "$PARAM_ARG"
}

run_destroy() {
  log_warn "Destroy mode enabled"
  log_warn "Resource Group to delete: $RESOURCE_GROUP"

  # Protección opcional
  if [[ "$ENV" == "prod" ]]; then
    log_error "Destroy is NOT allowed in prod"
    exit 1
  fi

  if [[ "$AUTO_APPROVE" != true ]]; then
    read -r -p "Are you sure you want to DELETE this Resource Group? (y/N): " answer
    case "$answer" in
      y|Y|yes|YES)
        ;;
      *)
        log_error "Aborted"
        exit 1
        ;;
    esac
  fi

  az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait

  log_info "Deletion initiated"
}

# -----------------------------
# Main
# -----------------------------
main() {
  parse_args "$@"
  pre_checks
  build_config
  show_plan
  confirm

  case "$MODE" in
    destroy)
      run_destroy
      ;;
    dry-run)
      ensure_rg
      run_dry
      ;;
    apply)
      ensure_rg
      run_apply
      ;;
  esac

  log_info "Done"
}

main "$@"

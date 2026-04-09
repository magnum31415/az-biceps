#!/bin/bash
set -e

# ================================
# LOAD CONFIG
# ================================
source ./config.sh

# ================================
# DEFAULTS
# ================================
MODE=""
AUTO_APPROVE=false

# ================================
# UTILS
# ================================
create_var () {
  NAME=$1
  VALUE=$2

  az resource create \
    --resource-group $RESOURCE_GROUP \
    --resource-type "Microsoft.Automation/automationAccounts/variables" \
    --name "$AUTOMATION_ACCOUNT/$NAME" \
    --properties "{\"value\":\"$VALUE\"}" \
    >/dev/null 2>&1 || echo "ℹ️ Variable $NAME already exists"
}

# ================================
# PARSE ARGS
# ================================
parse_args() {
  for arg in "$@"; do
    case $arg in
      --apply) MODE="apply" ;;
      --destroy) MODE="destroy" ;;
      --yes) AUTO_APPROVE=true ;;
      *) echo "❌ Unknown argument: $arg"; exit 1 ;;
    esac
  done

  if [[ -z "$MODE" ]]; then
    echo "❌ You must specify --apply or --destroy"
    exit 1
  fi
}

# ================================
# VALIDATIONS
# ================================
validate() {
  if [[ "$MODE" == "apply" && ! -f "./runbook.ps1" ]]; then
    echo "❌ runbook.ps1 not found"
    exit 1
  fi
}

# ================================
# SUMMARY
# ================================
print_summary() {
  echo "=========================================="
  echo "🚀 Automation Deployment Plan"
  echo "=========================================="
  echo "Mode:                $MODE"
  echo "Subscription:        $SUBSCRIPTION_ID"
  echo "Resource Group:      $RESOURCE_GROUP"
  echo "Automation Account:  $AUTOMATION_ACCOUNT"
  echo "Runbook:             $RUNBOOK_NAME"
  echo "Schedule:            $SCHEDULE_NAME"
  echo "Key Vault:           $KEYVAULT_NAME"
  echo "Storage Account:     $STORAGE_ACCOUNT"
  echo "=========================================="
}

# ================================
# CONFIRM
# ================================
confirm() {
  if [ "$AUTO_APPROVE" = false ]; then
    read -p "Do you want to continue? (y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
  fi
}

# ================================
# SET SUB
# ================================
set_subscription() {
  az account set --subscription $SUBSCRIPTION_ID
}

# ================================
# CREATE AUTOMATION ACCOUNT
# ================================
create_automation() {
  echo "🔹 Creating Automation Account..."
  az automation account create \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    >/dev/null 2>&1 || echo "ℹ️ Already exists"
}

verify_automation() {
  echo "🔍 Verifying Automation Account..."

  az automation account show \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    -o table
}

# ================================
# ENABLE MI
# ================================
enable_mi() {
  echo "🔹 Enabling Managed Identity..."

  RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT"

  az resource update \
    --ids $RESOURCE_ID \
    --set identity.type=SystemAssigned \
    >/dev/null

  echo "🔍 Waiting for MI..."

  for i in {1..10}; do
    MI_PRINCIPAL_ID=$(az automation account show \
      --name $AUTOMATION_ACCOUNT \
      --resource-group $RESOURCE_GROUP \
      --query identity.principalId -o tsv)

    [[ -n "$MI_PRINCIPAL_ID" && "$MI_PRINCIPAL_ID" != "null" ]] && break

    echo "⏳ Waiting ($i/10)..."
    sleep 5
  done

  [[ -z "$MI_PRINCIPAL_ID" || "$MI_PRINCIPAL_ID" == "null" ]] && {
    echo "❌ MI failed"
    exit 1
  }

  echo "✅ MI: $MI_PRINCIPAL_ID"
}

verify_mi() {
  echo "🔍 Verifying Managed Identity..."

  az automation account show \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query identity -o json
}

# ================================
# RBAC
# ================================
assign_rbac() {
  echo "🔹 Assigning RBAC..."

  KV_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEYVAULT_NAME"
  ST_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$STORAGE_RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

  for i in {1..5}; do
    az role assignment create \
      --assignee $MI_PRINCIPAL_ID \
      --role "Key Vault Administrator" \
      --scope $KV_SCOPE >/dev/null 2>&1 && break
    sleep 10
  done

  for i in {1..5}; do
    az role assignment create \
      --assignee $MI_PRINCIPAL_ID \
      --role "Storage Blob Data Contributor" \
      --scope $ST_SCOPE >/dev/null 2>&1 && break
    sleep 10
  done

  echo "🔍 Verifying RBAC..."
  az role assignment list \
    --assignee $MI_PRINCIPAL_ID \
    --query "[].roleDefinitionName" -o table
}

verify_rbac() {
  echo "🔍 Verifying RBAC..."

  az role assignment list \
    --assignee $MI_PRINCIPAL_ID \
    --query "[].{Role:roleDefinitionName, Scope:scope}" \
    -o table
}

# ================================
# RUNBOOK
# ================================
deploy_runbook() {
  echo "🔹 Deploying Runbook..."

  az automation runbook create \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $RUNBOOK_NAME \
    --type PowerShell >/dev/null 2>&1 || true

  az automation runbook replace-content \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $RUNBOOK_NAME \
    --content @runbook.ps1

  az automation runbook publish \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $RUNBOOK_NAME
}

verify_runbook() {
  echo "🔍 Verifying Runbook..."

  az automation runbook list \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    -o table
}

# ================================
# VARIABLES
# ================================
create_variables() {
  echo "🔹 Creating variables..."

  create_var "kvName" "$KEYVAULT_NAME"
  create_var "storageAccount" "$STORAGE_ACCOUNT"
  create_var "containerName" "$CONTAINER_NAME"
  create_var "subscriptionId" "$SUBSCRIPTION_ID"
}

verify_variables() {
  echo "🔍 Verifying Variables..."

  az resource list \
    --resource-group $RESOURCE_GROUP \
    --resource-type "Microsoft.Automation/automationAccounts/variables" \
    --query "[].name" \
    -o table
}

# ================================
# SCHEDULE
# ================================
create_schedule() {
  echo "🔹 Creating schedule..."

  START_TIME=$(date -u -d "+5 minutes" +"%Y-%m-%dT%H:%M:%SZ")

  az automation schedule create \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $SCHEDULE_NAME \
    --frequency Week \
    --interval 1 \
    --start-time $START_TIME >/dev/null 2>&1 || true

  az automation job schedule create \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --runbook-name $RUNBOOK_NAME \
    --schedule-name $SCHEDULE_NAME >/dev/null 2>&1 || true
}

verify_schedule() {
  echo "🔍 Verifying Schedule..."

  az automation schedule list \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    -o table
}

# ================================
# DESTROY
# ================================
destroy() {
  echo "🔹 Deleting Automation Account..."
  az automation account delete \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --yes
}

# ================================
# PRINT HEADER
# ================================
step() {
  echo ""
  echo "=========================================="
  echo "👉 $1"
  echo "=========================================="
}

# ================================
# MAIN
# ================================
main() {
  parse_args "$@"
  validate
  print_summary
  confirm
  set_subscription

  if [[ "$MODE" == "apply" ]]; then
    step "Automation Account"
    create_automation
    verify_automation

    step "Managed Identity"
    enable_mi
    verify_mi

    step "RBAC Assignments"
    assign_rbac
    verify_rbac || echo "⚠️ RBAC not fully propagated yet"

    step "Runbook Deployment"
    deploy_runbook
    verify_runbook

    step "Automation Variables"
    create_variables
    verify_variables

    step "Schedule"
    create_schedule
    verify_schedule
    echo "✅ Deployment completed"
  fi

  if [[ "$MODE" == "destroy" ]]; then
    destroy
  fi
}

main "$@"

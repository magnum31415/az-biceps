#!/bin/bash
set -e

# ================================
# LOAD CONFIG
# ================================
source ./config.sh

#RESOURCE_GROUP=$RESOURCE_GROUP_AUTOMATION
RESOURCE_GROUP="rg-ricard-pro-weu-01"
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

  echo "🔹 Creating/updating variable: $NAME"

  BODY=$(cat <<EOF
{
  "name": "$NAME",
  "properties": {
    "value": "\"$VALUE\"",
    "isEncrypted": false
  }
}
EOF
)

  az rest --method PUT \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT/variables/$NAME?api-version=2023-11-01" \
    --headers "Content-Type=application/json" \
    --body "$BODY" \
    >/dev/null

  echo "✅ Variable $NAME configured"
}

# ================================
# PARSE ARGS
# ================================
parse_args() {
  for arg in "$@"; do
    case $arg in
      --apply) MODE="apply" ;;
      --destroy) MODE="destroy" ;;
      --dry-run) MODE="dry-run" ;;
      --yes) AUTO_APPROVE=true ;;
      *) echo "❌ Unknown argument: $arg"; exit 1 ;;
    esac
  done

  if [[ -z "$MODE" ]]; then
    echo "❌ You must specify --apply, --destroy or --dry-run"
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
  if [[ "$MODE" == "dry-run" ]]; then
    echo "ℹ️ Dry-run mode → no changes will be applied"
    return
  fi

  if [ "$AUTO_APPROVE" = false ]; then
    read -p "Do you want to continue? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "❌ Cancelled"
      exit 0
    fi
  fi
}

# ================================
# SET SUB
# ================================
set_subscription() {
  az account set --subscription $SUBSCRIPTION_ID
}

# ================================
# VERIFY HELPERS
# ================================
get_mi_if_exists() {
  MI_PRINCIPAL_ID=$(az automation account show \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query identity.principalId -o tsv 2>/dev/null || echo "")

  [[ "$MI_PRINCIPAL_ID" == "null" ]] && MI_PRINCIPAL_ID=""
}

# ================================
# CREATE / VERIFY
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
    -o table || echo "⚠️ Not found"
}

enable_mi() {
  echo "🔹 Enabling Managed Identity..."

  RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT"

  az resource update \
    --ids $RESOURCE_ID \
    --set identity.type=SystemAssigned >/dev/null

  echo "🔍 Waiting for MI..."

  for i in {1..10}; do
    get_mi_if_exists
    [[ -n "$MI_PRINCIPAL_ID" ]] && break
    sleep 5
  done

  [[ -z "$MI_PRINCIPAL_ID" ]] && { echo "❌ MI failed"; exit 1; }

  echo "✅ MI: $MI_PRINCIPAL_ID"
}

verify_mi() {
  echo "🔍 Verifying Managed Identity..."
  az automation account show \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query identity -o json || echo "⚠️ MI not found"
}

get_mi_if_exists() {
  set +e
  MI_PRINCIPAL_ID=$(az automation account show \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query identity.principalId -o tsv 2>/dev/null)
  set -e

  if [[ "$MI_PRINCIPAL_ID" == "null" ]]; then
    MI_PRINCIPAL_ID=""
  fi

  return 0

}

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
}

verify_rbac() {
  echo "🔍 Verifying RBAC..."
  [[ -z "$MI_PRINCIPAL_ID" ]] && get_mi_if_exists

  [[ -z "$MI_PRINCIPAL_ID" ]] && {
    echo "⚠️ MI not found → cannot verify RBAC"
    return
  }

  az role assignment list \
    --assignee $MI_PRINCIPAL_ID \
    --all \
    --query "[].{Role:roleDefinitionName, Scope:scope}" \
    -o table || echo "⚠️ No RBAC yet"
}

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
    -o table || echo "⚠️ No runbooks"
}

create_variables() {
  echo "🔹 Creating variables..."
  create_var "kvName" "$KEYVAULT_NAME"
  create_var "storageAccount" "$STORAGE_ACCOUNT"
  create_var "containerName" "$CONTAINER_NAME"
  create_var "subscriptionId" "$SUBSCRIPTION_ID"
}

verify_variables() {
  echo "🔍 Verifying Variables..."

  az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT/variables?api-version=2023-11-01" \
    --query "value[].{Name:name, Value:properties.value}" \
    -o table
}

create_schedule() {
  echo "🔹 Creating schedule..."

  az automation schedule create \
    --automation-account-name "$AUTOMATION_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SCHEDULE_NAME" \
    --frequency "$FREQUENCY" \
    --interval 1 \
    --start-time "$START_TIME"

  echo "⏳ Waiting for schedule propagation..."
  sleep 10

  create_job_schedule_rest
}

create_job_schedule_rest() {
  echo "🔹 Creating job schedule link via REST..."

  JOB_SCHEDULE_GUID=$(uuidgen | tr '[:upper:]' '[:lower:]')

  az rest \
    --method PUT \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT/jobSchedules/$JOB_SCHEDULE_GUID?api-version=2024-10-23" \
    --headers "Content-Type=application/json" \
    --body "{
      \"properties\": {
        \"runbook\": {
          \"name\": \"$RUNBOOK_NAME\"
        },
        \"schedule\": {
          \"name\": \"$SCHEDULE_NAME\"
        },
        \"parameters\": {
          \"kvName\": \"$KEYVAULT_NAME\",
          \"storageAccount\": \"$STORAGE_ACCOUNT\",
          \"containerName\": \"$CONTAINER_NAME\",
          \"subscriptionId\": \"$SUBSCRIPTION_ID\"
        }
      }
    }"
}

verify_schedule() {
  echo "🔍 Verifying Schedule..."
  az automation schedule list \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    -o table || echo "⚠️ No schedules"
}

verify_job_schedule() {
  echo "🔍 Verifying Job Schedule (Runbook linkage)..."

  az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT/jobSchedules?api-version=2023-11-01" \
    --query "value[].{Runbook:properties.runbook.name, Schedule:properties.schedule.name}" \
    -o table
}

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

  # 🔹 DRY RUN → SOLO VERIFY
  if [[ "$MODE" == "dry-run" ]]; then
    step "Automation Account"
    verify_automation

    step "Managed Identity"
    verify_mi

    step "RBAC"
    verify_rbac

    step "Runbook"
    verify_runbook

    step "Variables"
    verify_variables

    step "Schedule"
    verify_job_schedule
    verify_schedule

    echo "✅ Dry-run completed"
    return
  fi

  if [[ "$MODE" == "apply" ]]; then
    step "Automation Account"
    create_automation
    verify_automation

    step "Managed Identity"
    enable_mi
    verify_mi

    step "RBAC Assignments"
    assign_rbac
    get_mi_if_exists
    verify_rbac || echo "⚠️ RBAC not fully propagated yet"

    step "Runbook Deployment"
    deploy_runbook
    verify_runbook

    step "Automation Variables"
    create_variables
    verify_variables

    step "Schedule"
    create_schedule
    verify_job_schedule
    verify_schedule

    echo "✅ Deployment completed"
  fi

  if [[ "$MODE" == "destroy" ]]; then
    destroy
  fi
}

main "$@"

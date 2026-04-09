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
# PARSE ARGS
# ================================
for arg in "$@"; do
  case $arg in
    --apply)
      MODE="apply"
      ;;
    --destroy)
      MODE="destroy"
      ;;
    --yes)
      AUTO_APPROVE=true
      ;;
    *)
      echo "❌ Unknown argument: $arg"
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "❌ You must specify --apply or --destroy"
  exit 1
fi

# ================================
# VALIDATIONS
# ================================
if [[ "$MODE" == "apply" ]]; then
  if [[ ! -f "./runbook.ps1" ]]; then
    echo "❌ runbook.ps1 not found in current directory"
    exit 1
  fi
fi

# ================================
# SUMMARY
# ================================
echo "=========================================="
echo "🚀 Automation Deployment Plan"
echo "=========================================="
echo "Mode:                $MODE"
echo "Subscription:        $SUBSCRIPTION_ID"
echo "Resource Group:      $RESOURCE_GROUP"
echo "Location:            $LOCATION"
echo "Automation Account:  $AUTOMATION_ACCOUNT"
echo "Runbook:             $RUNBOOK_NAME"
echo "Schedule:            $SCHEDULE_NAME"
echo "Key Vault:           $KEYVAULT_NAME"
echo "Storage Account:     $STORAGE_ACCOUNT"
echo "Container:           $CONTAINER_NAME"
echo "Runbook file:        runbook.ps1"
echo "=========================================="

# ================================
# CONFIRMATION
# ================================
if [ "$AUTO_APPROVE" = false ]; then
  read -p "Do you want to continue? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Aborted"
    exit 0
  fi
fi

# ================================
# SET SUBSCRIPTION
# ================================
az account set --subscription $SUBSCRIPTION_ID

# ================================
# APPLY
# ================================
if [[ "$MODE" == "apply" ]]; then

  echo "🔹 Creating Automation Account..."
  az automation account create \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    >/dev/null 2>&1 || echo "ℹ️ Automation Account already exists"


echo "🔹 Enabling Managed Identity..."

RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT"

# Enable MI via ARM (siempre funciona)
az resource update \
  --ids $RESOURCE_ID \
  --set identity.type=SystemAssigned \
  >/dev/null

# ================================
# VERIFY (loop hasta que exista)
# ================================
echo "🔍 Waiting for Managed Identity to be available..."

for i in {1..10}; do
  MI_PRINCIPAL_ID=$(az automation account show \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query identity.principalId -o tsv)

  if [[ -n "$MI_PRINCIPAL_ID" && "$MI_PRINCIPAL_ID" != "null" ]]; then
    echo "✅ Managed Identity enabled: $MI_PRINCIPAL_ID"
    break
  fi

  echo "⏳ Waiting... ($i/10)"
  sleep 5
done

# ================================
# FAIL SI NO HAY MI
# ================================
if [[ -z "$MI_PRINCIPAL_ID" || "$MI_PRINCIPAL_ID" == "null" ]]; then
  echo "❌ Failed to enable Managed Identity"
  exit 1
fi

  MI_PRINCIPAL_ID=$(az automation account show \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query identity.principalId -o tsv)

  echo "🔹 Managed Identity Principal ID: $MI_PRINCIPAL_ID"

  echo "🔹 Assigning Key Vault permissions..."
  az role assignment create \
    --assignee $MI_PRINCIPAL_ID \
    --role "Key Vault Administrator" \
    --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEYVAULT_NAME \
    >/dev/null 2>&1 || echo "ℹ️ KV role already assigned"

  echo "🔹 Assigning Storage permissions..."
  az role assignment create \
    --assignee $MI_PRINCIPAL_ID \
    --role "Storage Blob Data Contributor" \
    --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$STORAGE_RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT \
    >/dev/null 2>&1 || echo "ℹ️ Storage role already assigned"

  echo "🔹 Creating Runbook..."
  az automation runbook create \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $RUNBOOK_NAME \
    --type PowerShell \
    >/dev/null 2>&1 || echo "ℹ️ Runbook already exists"

  echo "🔹 Uploading Runbook content..."
  az automation runbook replace-content \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $RUNBOOK_NAME \
    --content @runbook.ps1

  echo "🔹 Publishing Runbook..."
  az automation runbook publish \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $RUNBOOK_NAME

  echo "🔹 Creating Schedule..."
  az automation schedule create \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $SCHEDULE_NAME \
    --frequency Week \
    --interval 1 \
    >/dev/null 2>&1 || echo "ℹ️ Schedule already exists"

  echo "🔹 Linking Runbook + Schedule..."
  az automation job schedule create \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --runbook-name $RUNBOOK_NAME \
    --schedule-name $SCHEDULE_NAME \
    >/dev/null 2>&1 || echo "ℹ️ Already linked"

  echo "✅ Deployment completed successfully"

fi

# ================================
# DESTROY
# ================================
if [[ "$MODE" == "destroy" ]]; then

  echo "🔹 Deleting Automation Account..."
  az automation account delete \
    --name $AUTOMATION_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --yes

  echo "⚠️ Note: Role assignments are NOT automatically removed"

  echo "✅ Destroy completed"

fi

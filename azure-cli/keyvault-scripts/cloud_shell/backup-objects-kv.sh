#!/bin/bash
set -e

source ./config.sh

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="/tmp/kv-backup-$TIMESTAMP"

mkdir -p $BACKUP_DIR

echo "🔹 Backing up secrets..."
for s in $(az keyvault secret list --vault-name $KV_NAME --query "[].name" -o tsv); do
  echo "  - $s"
  az keyvault secret backup \
    --vault-name $KV_NAME \
    --name $s \
    --file "$BACKUP_DIR/secret-$s.bak"
done

echo "🔹 Backing up keys..."
for k in $(az keyvault key list --vault-name $KV_NAME --query "[].name" -o tsv); do
  echo "  - $k"
  az keyvault key backup \
    --vault-name $KV_NAME \
    --name $k \
    --file "$BACKUP_DIR/key-$k.bak"
done

echo "🔹 Backing up certs..."
for c in $(az keyvault certificate list --vault-name $KV_NAME --query "[].name" -o tsv); do
  echo "  - $c"
  az keyvault certificate backup \
    --vault-name $KV_NAME \
    --name $c \
    --file "$BACKUP_DIR/cert-$c.bak"
done

echo "🔹 Uploading to Storage..."

az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --destination "$CONTAINER_NAME/$KV_NAME/$TIMESTAMP" \
  --source $BACKUP_DIR \
  --auth-mode login

echo "✅ Backup completed: $TIMESTAMP"

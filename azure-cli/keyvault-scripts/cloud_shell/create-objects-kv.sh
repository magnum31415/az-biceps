#!/bin/bash
set -e

source ./config.sh

echo "🔹 Creating secrets..."
for i in {1..3}; do
  az keyvault secret set \
    --vault-name $KV_NAME \
    --name "test-secret-$i" \
    --value "value-$i"
done

echo "🔹 Creating keys..."
for i in {1..3}; do
  az keyvault key create \
    --vault-name $KV_NAME \
    --name "test-key-$i" \
    --kty RSA
done

echo "🔹 Creating certificates..."
for i in {1..3}; do
  az keyvault certificate create \
    --vault-name $KV_NAME \
    --name "test-cert-$i" \
    --policy "$(az keyvault certificate get-default-policy)"
done

echo "✅ Objects created"

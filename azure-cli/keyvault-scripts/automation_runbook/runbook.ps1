param(
    [Parameter(Mandatory=$true)]
    [string]$kvName,

    [Parameter(Mandatory=$true)]
    [string]$storageAccount,

    [Parameter(Mandatory=$true)]
    [string]$containerName,

    [Parameter(Mandatory=$true)]
    [string]$subscriptionId
)


# ================================
# LOGIN (Managed Identity)
# ================================
Write-Output "🔐 Logging in with Managed Identity..."
Connect-AzAccount -Identity | Out-Null
Set-AzContext -Subscription $subscriptionId | Out-Null

# ================================
# INIT
# ================================
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempPath = Join-Path $env:TEMP "kv-backup-$timestamp"

Write-Output "📁 Creating temp folder: $tempPath"
New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

# ================================
# BACKUP SECRETS (EXCLUDING CERT SECRETS)
# ================================
Write-Output "🔹 Backing up secrets..."

try {
    $secrets = Get-AzKeyVaultSecret -VaultName $kvName | Where-Object {
        # Excluir secretos asociados a certificados (contentType típico)
        $_.ContentType -notmatch "application/x-pkcs12"
    }

    foreach ($s in $secrets) {
        $file = Join-Path $tempPath "secret-$($s.Name).bak"
        Write-Output "  - Secret: $($s.Name)"

        Backup-AzKeyVaultSecret `
            -VaultName $kvName `
            -Name $s.Name `
            -OutputFile $file
    }
}
catch {
    Write-Error "❌ Error backing up secrets: $_"
    throw
}

# ================================
# BACKUP KEYS
# ================================
Write-Output "🔹 Backing up keys..."

try {
    $keys = Get-AzKeyVaultKey -VaultName $kvName

    foreach ($k in $keys) {
        $file = Join-Path $tempPath "key-$($k.Name).bak"
        Write-Output "  - Key: $($k.Name)"

        Backup-AzKeyVaultKey `
            -VaultName $kvName `
            -Name $k.Name `
            -OutputFile $file
    }
}
catch {
    Write-Error "❌ Error backing up keys: $_"
    throw
}

# ================================
# BACKUP CERTIFICATES (SOLO CERT)
# ================================
Write-Output "🔹 Backing up certificates..."

try {
    $certs = Get-AzKeyVaultCertificate -VaultName $kvName

    foreach ($c in $certs) {
        $file = Join-Path $tempPath "cert-$($c.Name).bak"
        Write-Output "  - Certificate: $($c.Name)"

        Backup-AzKeyVaultCertificate `
            -VaultName $kvName `
            -Name $c.Name `
            -OutputFile $file
    }
}
catch {
    Write-Error "❌ Error backing up certificates: $_"
    throw
}

# ================================
# UPLOAD TO STORAGE
# ================================
Write-Output "🔹 Uploading backups to storage..."

try {
    $ctx = New-AzStorageContext `
        -StorageAccountName $storageAccount `
        -UseConnectedAccount

    $uploadedBlobs = @()

    foreach ($file in Get-ChildItem $tempPath) {

        $blobName = "$kvName/$timestamp/$($file.Name)"
        $blobUrl  = "https://$storageAccount.blob.core.windows.net/$containerName/$blobName"

        Write-Output "  - Uploading: $blobName"
        Write-Output "    URL: $blobUrl"

        Set-AzStorageBlobContent `
            -File $file.FullName `
            -Container $containerName `
            -Blob $blobName `
            -Context $ctx `
            -Force | Out-Null

        $uploadedBlobs += $blobName
    }
}
catch {
    Write-Error "❌ Error uploading to storage: $_"
    throw
}

# ================================
# VERIFY UPLOAD
# ================================
Write-Output "🔍 Verifying uploaded blobs in storage..."

try {
    $prefix = "$kvName/$timestamp/"

    $blobs = Get-AzStorageBlob `
        -Container $containerName `
        -Context $ctx `
        -Prefix $prefix

    if ($blobs.Count -eq 0) {
        throw "❌ No blobs found in storage under prefix: $prefix"
    }

    Write-Output "✅ Found $($blobs.Count) blobs in storage:"

    foreach ($b in $blobs) {
        $url = "https://$storageAccount.blob.core.windows.net/$containerName/$($b.Name)"
        Write-Output "  - $url"
    }
}
catch {
    Write-Error "❌ Verification failed: $_"
    throw
}


# ================================
# CLEANUP
# ================================
Write-Output "🧹 Cleaning up temp files..."
Remove-Item -Path $tempPath -Recurse -Force

# ================================
# DONE
# ================================
Write-Output "✅ Key Vault backup completed successfully"
Write-Output "📦 Path: $kvName/$timestamp"
Write-Output "🏁 Process finished successfully at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"


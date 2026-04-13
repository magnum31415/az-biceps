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
# BACKUP SECRETS (EXCLUDING CERT PFX)
# ================================
Write-Output "🔹 Backing up secrets..."

try {
    $secrets = Get-AzKeyVaultSecret -VaultName $kvName | Where-Object {
        $_.ContentType -notmatch "application/x-pkcs12"
    }

    foreach ($s in $secrets) {
        $file = Join-Path $tempPath "secret-$($s.Name)-$($s.Version).bak"
        Write-Output "  - Secret: $($s.Name)"

        Backup-AzKeyVaultSecret `
            -VaultName $kvName `
            -Name $s.Name `
            -OutputFile $file

        if ((Get-Item $file).Length -eq 0) {
            throw "❌ Empty backup file for secret: $($s.Name)"
        }
    }
}
catch {
    Write-Error "❌ Error backing up secrets: $_"
    throw
}

# ================================
# BACKUP KEYS (EXCLUDING CERT KEYS)
# ================================
Write-Output "🔹 Backing up keys..."

try {
    $keys = Get-AzKeyVaultKey -VaultName $kvName
    $certNames = (Get-AzKeyVaultCertificate -VaultName $kvName).Name

    foreach ($k in $keys) {

        # ❗ Skip keys that belong to certificates (match by name)
        if ($certNames -contains $k.Name) {
            Write-Output "  ⚠️ Skipping certificate key: $($k.Name)"
            continue
        }

        $file = Join-Path $tempPath "key-$($k.Name)-$($k.Version).bak"
        Write-Output "  - Key: $($k.Name)"

        Backup-AzKeyVaultKey `
            -VaultName $kvName `
            -Name $k.Name `
            -OutputFile $file

        if (!(Test-Path $file) -or (Get-Item $file).Length -eq 0) {
            throw "❌ Empty backup file for key: $($k.Name)"
        }
    }
}
catch {
    Write-Error "❌ Error backing up keys: $_"
    throw
}


# ================================
# BACKUP CERTIFICATES (FULL BACKUP)
# ================================

Write-Output "🔹 Backing up certificates (FULL)..."

try {
    $certs = Get-AzKeyVaultCertificate -VaultName $kvName

    foreach ($c in $certs) {

        $file = Join-Path $tempPath "cert-$($c.Name)-$($c.Version).bak"

        Write-Output "  - Certificate: $($c.Name)"

        Backup-AzKeyVaultCertificate `
            -VaultName $kvName `
            -Name $c.Name `
            -OutputFile $file

        if (!(Test-Path $file) -or (Get-Item $file).Length -eq 0) {
            throw "❌ Empty backup file for certificate: $($c.Name)"
        }
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

    foreach ($file in Get-ChildItem $tempPath) {

        $blobName = "$kvName/$timestamp/$($file.Name)"
        $blobUrl  = "https://$storageAccount.blob.core.windows.net/$containerName/$blobName"

        Write-Output "  - Uploading: $blobName"

        Set-AzStorageBlobContent `
            -File $file.FullName `
            -Container $containerName `
            -Blob $blobName `
            -Context $ctx `
            -Force | Out-Null
    }
}
catch {
    Write-Error "❌ Error uploading to storage: $_"
    throw
}

# ================================
# VERIFY UPLOAD
# ================================
Write-Output "🔍 Verifying uploaded blobs..."

try {
    $prefix = "$kvName/$timestamp/"

    $blobs = Get-AzStorageBlob `
        -Container $containerName `
        -Context $ctx `
        -Prefix $prefix

    if ($blobs.Count -eq 0) {
        throw "❌ No blobs found in storage"
    }

    Write-Output "✅ Found $($blobs.Count) blobs:"
    $blobs | ForEach-Object {
        Write-Output "  - $($_.Name)"
    }
}
catch {
    Write-Error "❌ Verification failed: $_"
    throw
}

# ================================
# CLEANUP
# ================================
Write-Output "🧹 Cleaning temp files..."
Remove-Item -Path $tempPath -Recurse -Force

# ================================
# DONE
# ================================
Write-Output "✅ Key Vault backup completed"
Write-Output "📦 Path: $kvName/$timestamp"
Write-Output "🏁 Finished at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

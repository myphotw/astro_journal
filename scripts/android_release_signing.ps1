[CmdletBinding()]
param([switch]$CreateKey)

$ErrorActionPreference = 'Stop'

function Get-AstroJournalSigningDirectory {
    return Join-Path $env:USERPROFILE '.astrojournal-signing\release'
}

function Clear-AstroJournalReleaseSigning {
    foreach ($name in @('ASTROJOURNAL_RELEASE_STORE_FILE', 'ASTROJOURNAL_RELEASE_STORE_PASSWORD',
        'ASTROJOURNAL_RELEASE_KEY_ALIAS', 'ASTROJOURNAL_RELEASE_KEY_PASSWORD')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
}

function Enable-AstroJournalReleaseSigning {
    $directory = Get-AstroJournalSigningDirectory
    $store = Join-Path $directory 'astrojournal-release.p12'
    $passwordFile = Join-Path $directory 'password.dpapi'
    $certificate = Join-Path $directory 'release-public.cer'
    foreach ($path in @($store, $passwordFile, $certificate)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'Release signing is not initialized. Run scripts/android_release_signing.ps1 -CreateKey once.'
        }
    }
    $secure = Get-Content -LiteralPath $passwordFile -Raw | ConvertTo-SecureString
    $credential = [PSCredential]::new('AstroJournalRelease', $secure)
    $env:ASTROJOURNAL_RELEASE_STORE_FILE = $store
    $env:ASTROJOURNAL_RELEASE_KEY_ALIAS = 'astrojournal-release'
    $env:ASTROJOURNAL_RELEASE_STORE_PASSWORD = $credential.GetNetworkCredential().Password
    $env:ASTROJOURNAL_RELEASE_KEY_PASSWORD = $env:ASTROJOURNAL_RELEASE_STORE_PASSWORD
    return (Get-FileHash -LiteralPath $certificate -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-AstroJournalReleaseKey {
    $directory = Get-AstroJournalSigningDirectory
    if ((Test-Path -LiteralPath $directory) -and
        (Get-ChildItem -LiteralPath $directory -Force | Select-Object -First 1)) {
        throw 'Signing directory is not empty. Existing signing material will never be overwritten.'
    }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    # Protect files before generating credentials. No inherited broad access.
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach ($sid in @($owner, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    $acl.SetOwner($owner)
    Set-Acl -LiteralPath $directory -AclObject $acl

    $random = New-Object byte[] 48
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $password = [Convert]::ToBase64String($random)
    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $secure
    [IO.File]::WriteAllText((Join-Path $directory 'password.dpapi'), $encrypted)
    $env:ASTROJOURNAL_RELEASE_STORE_PASSWORD = $password
    $env:ASTROJOURNAL_RELEASE_KEY_PASSWORD = $password
    $password = $null
    try {
        $keytool = (Get-Command keytool -ErrorAction Stop).Source
        $store = Join-Path $directory 'astrojournal-release.p12'
        $result = & $keytool -genkeypair -keystore $store -storetype PKCS12 `
            -storepass:env ASTROJOURNAL_RELEASE_STORE_PASSWORD `
            -keypass:env ASTROJOURNAL_RELEASE_KEY_PASSWORD `
            -alias astrojournal-release -keyalg RSA -keysize 3072 -validity 36500 `
            -dname 'CN=AstroJournal Personal Release,O=Personal,C=KR' 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Release key generation failed. Signing material was retained for inspection.' }
        $certificate = Join-Path $directory 'release-public.cer'
        $result = & $keytool -exportcert -keystore $store `
            -storepass:env ASTROJOURNAL_RELEASE_STORE_PASSWORD `
            -alias astrojournal-release -file $certificate 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Public certificate export failed.' }
        Write-Host "Release signing directory: $directory"
        Write-Host ('Release certificate SHA-256: ' + (Get-FileHash -LiteralPath $certificate -Algorithm SHA256).Hash)
        Write-Host 'Password is stored with Windows DPAPI protection, never printed.'
    }
    finally { Clear-AstroJournalReleaseSigning }
}

if ($CreateKey) { New-AstroJournalReleaseKey }

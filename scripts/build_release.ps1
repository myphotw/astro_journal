[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'config\local.env'
$temporaryDefines = $null

function Read-LocalBuildConfig {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Missing config/local.env. Copy config/local.env.example and fill the required values.'
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { continue }
        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        $values[$name] = $value
    }
    return $values
}

try {
    $config = Read-LocalBuildConfig -Path $configPath
    foreach ($requiredName in @('GOOGLE_MAPS_API_KEY', 'TC_BACKEND_AUTH_TOKEN')) {
        if (-not $config.ContainsKey($requiredName) -or [string]::IsNullOrWhiteSpace($config[$requiredName])) {
            throw "Missing required build setting: $requiredName"
        }
    }

    $env:GOOGLE_MAPS_API_KEY = $config['GOOGLE_MAPS_API_KEY']
    $env:TC_BACKEND_AUTH_TOKEN = $config['TC_BACKEND_AUTH_TOKEN']

    $defines = @{ TC_BACKEND_AUTH_TOKEN = $config['TC_BACKEND_AUTH_TOKEN'] }
    if ($config.ContainsKey('TC_BACKEND_URL') -and -not [string]::IsNullOrWhiteSpace($config['TC_BACKEND_URL'])) {
        $defines['TC_BACKEND_URL'] = $config['TC_BACKEND_URL']
    }
    $temporaryDefines = Join-Path ([IO.Path]::GetTempPath()) ("astro-journal-defines-{0}.json" -f [guid]::NewGuid())
    $json = $defines | ConvertTo-Json -Compress
    [IO.File]::WriteAllText(
        $temporaryDefines,
        $json,
        [Text.UTF8Encoding]::new($false)
    )

    Push-Location $projectRoot
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
        flutter build apk --release --dart-define-from-file=$temporaryDefines
        if ($LASTEXITCODE -ne 0) { throw 'Release APK build failed.' }

        $apk = Get-Item -LiteralPath (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk')
        Write-Host ("Release APK: {0}" -f $apk.FullName)
        Write-Host ("Size: {0:N0} bytes" -f $apk.Length)
    }
    finally {
        Pop-Location
    }
}
finally {
    Remove-Item Env:\GOOGLE_MAPS_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\TC_BACKEND_AUTH_TOKEN -ErrorAction SilentlyContinue
    if ($temporaryDefines -and (Test-Path -LiteralPath $temporaryDefines)) {
        Remove-Item -LiteralPath $temporaryDefines -Force
    }
}

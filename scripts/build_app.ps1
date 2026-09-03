[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Mode = 'Debug',
    [ValidateSet('Android', 'Windows')]
    [string]$TargetPlatform = 'Android'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'config\local.env'
$temporaryDefines = $null
$variant = $Mode.ToLowerInvariant()
$isAndroidBuild = $TargetPlatform -eq 'Android'

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
    $requiredNames = @('TC_BACKEND_AUTH_TOKEN')
    if ($isAndroidBuild) {
        $requiredNames += 'GOOGLE_MAPS_API_KEY'
    }
    foreach ($requiredName in $requiredNames) {
        if (-not $config.ContainsKey($requiredName) -or [string]::IsNullOrWhiteSpace($config[$requiredName])) {
            throw "Missing required build setting: $requiredName"
        }
    }

    # Android Gradle reads Maps from the environment. The token and optional
    # backend URL are compile-time Dart defines for both Android and Windows.
    # Values are never written to logs.
    if ($isAndroidBuild) {
        $env:GOOGLE_MAPS_API_KEY = $config['GOOGLE_MAPS_API_KEY']
    }
    $env:TC_BACKEND_AUTH_TOKEN = $config['TC_BACKEND_AUTH_TOKEN']

    $defines = @{ TC_BACKEND_AUTH_TOKEN = $config['TC_BACKEND_AUTH_TOKEN'] }
    if ($config.ContainsKey('TC_BACKEND_URL') -and -not [string]::IsNullOrWhiteSpace($config['TC_BACKEND_URL'])) {
        $defines['TC_BACKEND_URL'] = $config['TC_BACKEND_URL']
    }
    $backendUrlSource = if ($defines.ContainsKey('TC_BACKEND_URL')) { 'local_env' } else { 'app_default' }
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

        if ($isAndroidBuild) {
            flutter build apk "--$variant" "--dart-define-from-file=$temporaryDefines"
            if ($LASTEXITCODE -ne 0) { throw "$Mode APK build failed." }

            $mapsResourcePath = Join-Path $projectRoot "build\app\generated\res\resValues\$variant\values\gradleResValues.xml"
            if (-not (Test-Path -LiteralPath $mapsResourcePath -PathType Leaf)) {
                throw "$Mode Google Maps resource was not generated."
            }
            [xml]$mapsResource = Get-Content -LiteralPath $mapsResourcePath
            $mapsValue = $mapsResource.resources.string |
                Where-Object { $_.name -eq 'google_maps_api_key' } |
                Select-Object -First 1
            if ($null -eq $mapsValue -or $mapsValue.InnerText -ne $config['GOOGLE_MAPS_API_KEY']) {
                throw "$Mode Google Maps resource does not match the configured build input."
            }

            $mergedManifestPath = Join-Path $projectRoot "build\app\intermediates\merged_manifests\$variant\process$($Mode)Manifest\AndroidManifest.xml"
            if (-not (Test-Path -LiteralPath $mergedManifestPath -PathType Leaf) -or
                -not (Select-String -LiteralPath $mergedManifestPath -SimpleMatch 'android:name="com.google.android.geo.API_KEY"' -Quiet) -or
                -not (Select-String -LiteralPath $mergedManifestPath -SimpleMatch 'android:value="@string/google_maps_api_key"' -Quiet)) {
                throw "$Mode manifest does not reference the generated Google Maps resource."
            }
        }
        else {
            flutter build windows "--$variant" "--dart-define-from-file=$temporaryDefines"
            if ($LASTEXITCODE -ne 0) { throw "$Mode Windows build failed." }
        }

        $decodedDefines = Get-Content -LiteralPath $temporaryDefines -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($decodedDefines.TC_BACKEND_AUTH_TOKEN) -or
            $decodedDefines.TC_BACKEND_AUTH_TOKEN -ne $config['TC_BACKEND_AUTH_TOKEN']) {
            throw "$Mode Backend token build input is not configured."
        }

        if ($isAndroidBuild) {
            Write-Host 'MAPS_RESOURCE_CONFIGURED=true'
        }
        Write-Host 'BACKEND_TOKEN_BUILD_CONFIGURED=true'
        Write-Host ("BACKEND_URL_BUILD_CONFIGURED={0}" -f $backendUrlSource)

        if ($isAndroidBuild) {
            $apk = Get-Item -LiteralPath (Join-Path $projectRoot "build\app\outputs\flutter-apk\app-$variant.apk")
            Write-Host ("{0} APK: {1}" -f $Mode, $apk.FullName)
            Write-Host ("Size: {0:N0} bytes" -f $apk.Length)
        }
        else {
            $exe = Get-Item -LiteralPath (Join-Path $projectRoot "build\windows\x64\runner\$Mode\astro_journal.exe")
            Write-Host ("{0} Windows EXE: {1}" -f $Mode, $exe.FullName)
            Write-Host ("Size: {0:N0} bytes" -f $exe.Length)
        }
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

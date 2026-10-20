[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('android', 'windows', 'all')]
    [string]$Target
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$distRoot = Join-Path $projectRoot 'dist'
$distFullPath = [IO.Path]::GetFullPath($distRoot).TrimEnd('\', '/')
if (-not $distFullPath.StartsWith(
    "$([IO.Path]::GetFullPath($projectRoot).TrimEnd('\', '/'))\",
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'The dist folder must be inside the project.'
}

function Assert-DistChild {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith(
        "$distFullPath\",
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to change a path outside dist: $fullPath"
    }
}

function Assert-File {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required build output is missing: $Path"
    }
}

function Assert-NotLink {
    param([Parameter(Mandatory)][string]$Path)
    if ((Test-Path -LiteralPath $Path) -and
        ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to replace a linked build folder: $Path"
    }
}

function Publish-Platform {
    param([Parameter(Mandatory)][ValidateSet('android', 'windows')][string]$Platform)

    $platformName = if ($Platform -eq 'android') { 'Android' } else { 'Windows' }
    Write-Host "$platformName Release build started."
    & (Join-Path $projectRoot 'scripts\build_app.ps1') -Mode Release -TargetPlatform $platformName
    if (-not $?) {
        throw "$platformName Release build failed; the existing dist package was kept."
    }

    Assert-NotLink $distRoot
    New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
    $stagePath = Join-Path $distRoot (".stage-$Platform-" + [guid]::NewGuid().ToString('N'))
    $destination = Join-Path $distRoot $Platform
    $backupPath = Join-Path $distRoot (".backup-$Platform-" + [guid]::NewGuid().ToString('N'))
    Assert-DistChild $stagePath
    Assert-DistChild $destination
    Assert-DistChild $backupPath
    Assert-NotLink $destination
    $oldMoved = $false
    $published = $false

    try {
        if ($Platform -eq 'android') {
            $sourceApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
            Assert-File $sourceApk
            New-Item -ItemType Directory -Path $stagePath | Out-Null
            Copy-Item -LiteralPath $sourceApk -Destination (Join-Path $stagePath 'AstroJournal.apk')
            Assert-File (Join-Path $stagePath 'AstroJournal.apk')
        } else {
            $sourceRelease = Join-Path $projectRoot 'build\windows\x64\runner\Release'
            if (-not (Test-Path -LiteralPath $sourceRelease -PathType Container)) {
                throw "Windows Release folder is missing: $sourceRelease"
            }
            Copy-Item -LiteralPath $sourceRelease -Destination $stagePath -Recurse
            $originalExe = Join-Path $stagePath 'astro_journal.exe'
            Assert-File $originalExe
            Rename-Item -LiteralPath $originalExe -NewName 'AstroJournal.exe'
            foreach ($relativePath in @(
                'AstroJournal.exe',
                'flutter_windows.dll',
                'sqlite3.dll',
                'data\app.so',
                'data\icudtl.dat',
                'data\flutter_assets\AssetManifest.bin'
            )) {
                Assert-File (Join-Path $stagePath $relativePath)
            }
        }

        if ($Platform -eq 'windows' -and (Test-Path -LiteralPath $destination)) {
            $destinationFullPath = [IO.Path]::GetFullPath($destination).TrimEnd('\', '/')
            foreach ($process in (Get-Process -Name 'AstroJournal', 'astro_journal' -ErrorAction SilentlyContinue)) {
                $processPath = $null
                try { $processPath = $process.Path } catch { }
                if ($processPath -and [IO.Path]::GetFullPath($processPath).StartsWith(
                    "$destinationFullPath\",
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                    throw "Close the running Windows app before replacing $destination"
                }
            }
        }

        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination $backupPath -ErrorAction Stop
            $oldMoved = $true
        }
        Move-Item -LiteralPath $stagePath -Destination $destination -ErrorAction Stop
        $published = $true
    } catch {
        if ($oldMoved -and -not (Test-Path -LiteralPath $destination) -and
            (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $destination -ErrorAction Stop
        }
        throw "Deployment failed for $platformName; previous package retained where possible. $($_.Exception.Message)"
    } finally {
        if (Test-Path -LiteralPath $stagePath) {
            Remove-Item -LiteralPath $stagePath -Recurse -Force
        }
    }

    if ($published -and (Test-Path -LiteralPath $backupPath)) {
        try {
            Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Old package cleanup failed; backup remains at $backupPath"
        }
    }
    if ($Platform -eq 'android') {
        Write-Host "Android build and deployment succeeded: $(Join-Path $destination 'AstroJournal.apk')"
    } else {
        Write-Host "Windows build and deployment succeeded: $(Join-Path $destination 'AstroJournal.exe')"
        Write-Host "Windows package folder: $destination"
    }
}

if ($Target -eq 'all') {
    Publish-Platform android
    Publish-Platform windows
} else {
    Publish-Platform $Target
}

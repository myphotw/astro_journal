#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$migration = Join-Path $PSScriptRoot '../scripts/initialize_famous_celestial_objects.ps1'
$seed = @(Get-Content (Join-Path $PSScriptRoot '../scripts/famous_celestial_objects_initial_ids.json') -Raw | ConvertFrom-Json)
$sandbox = [IO.Directory]::CreateTempSubdirectory('astro-famous-test-')
$origin = 'https://example.invalid'
$oldToken = $env:TC_BACKEND_AUTH_TOKEN
$env:TC_BACKEND_AUTH_TOKEN = 'fake-test-token'
$server = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$calls = [System.Collections.Generic.List[string]]::new()

function Start-Sleep { param($Seconds, $Milliseconds) }

function Invoke-WebRequest {
    param($Uri, $Method, $Headers, $TimeoutSec, $MaximumRedirection, $ErrorAction, $ContentType, $Body)
    if ([uri]$Uri -notlike 'https://example.invalid/api/astro/catalog-favorites*') { throw 'Unexpected test URI.' }
    if ($Headers.Authorization -ne 'Bearer fake-test-token') { throw 'Missing test credentials.' }
    if ($Method -eq 'GET') {
        $calls.Add('GET')
        $rows = @($server | ForEach-Object {
            [pscustomobject]@{catalog_object_id = $_; created_at = '2026-01-01T00:00:00Z'; updated_at = '2026-01-01T00:00:00Z'}
        })
        return [pscustomobject]@{ Content = (ConvertTo-Json -InputObject $rows -Compress) }
    }
    $id = if ($Method -eq 'POST') { ($Body | ConvertFrom-Json).catalog_object_id } else {
        [uri]::UnescapeDataString(([uri]$Uri).Segments[-1])
    }
    $calls.Add("$Method $id")
    if ("$Method $id" -ceq $failRequest) { throw [FormatException]::new('simulated request failure') }
    if ($Method -eq 'POST') {
        [void]$server.Add($id)
        return [pscustomobject]@{ Content = (@{catalog_object_id = $id} | ConvertTo-Json -Compress) }
    }
    $body = @{catalog_object_id = $id; deleted = $server.Remove($id)} | ConvertTo-Json -Compress
    return [pscustomobject]@{ Content = $body }
}

function Assert-True($Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

try {
    [void]$server.Add('custom-original')
    [void]$server.Add($seed[0])
    $firstJournal = Join-Path $sandbox.FullName 'resume-case'
    $preview = & $migration -BaseUrl $origin -JournalDirectory $firstJournal
    Assert-True ($preview.Adds -eq 316 -and $preview.Removes -eq 1 -and $calls.Count -eq 1) 'Preview sent writes or counted incorrectly.'
    Assert-True (-not (Test-Path -LiteralPath $firstJournal)) 'Preview created a journal.'

    $refusedDelete = $false
    try { $null = & $migration -BaseUrl $origin -Apply -ClientsClosed -ForbidRemovals -JournalDirectory $firstJournal }
    catch { $refusedDelete = $_.Exception.Message -like 'Removals are forbidden*' }
    Assert-True ($refusedDelete -and -not ($calls -like 'POST *') -and -not ($calls -like 'DELETE *')) 'No-deletion guard allowed writes.'

    $refusedDelete = $false
    try { $null = & $migration -BaseUrl $origin -Apply -ClientsClosed -ForbidRemovals -JournalDirectory $firstJournal }
    catch { $refusedDelete = $_.Exception.Message -like 'Removals are forbidden*' }
    Assert-True ($refusedDelete -and -not ($calls -like 'POST *') -and -not ($calls -like 'DELETE *')) 'No-deletion guard allowed writes.'

    $failRequest = "POST $($seed[2])"
    $failed = $false
    try { $null = & $migration -BaseUrl $origin -Apply -ClientsClosed -JournalDirectory $firstJournal }
    catch { $failed = $_.Exception.Message -like 'Favorites POST failed*' }
    Assert-True $failed 'A failing POST did not stop the operation.'
    Assert-True ($server.Contains('custom-original') -and -not ($calls -like 'DELETE *')) 'Deleted before all seeds were available.'
    $failRequest = ''
    $result = & $migration -BaseUrl $origin -Resume -ClientsClosed -JournalDirectory $firstJournal
    Assert-True ($result.Verified -eq 317 -and $server.SetEquals([string[]]$seed)) 'Resume did not verify the 317 seed IDs.'

    [void]$server.Remove($seed[0])
    [void]$server.Add('user-after-setup')
    $calls.Clear()
    $blocked = $false
    try { $null = & $migration -BaseUrl $origin -Apply -ClientsClosed -JournalDirectory $firstJournal }
    catch { $blocked = $_.Exception.Message -like 'Migration is closed*' }
    Assert-True ($blocked -and $calls.Count -eq 0 -and $server.Contains('user-after-setup')) 'Second apply overwrote post-migration user changes.'

    $server.Clear()
    [void]$server.Add('custom-original')
    [void]$server.Add($seed[0])
    $secondJournal = Join-Path $sandbox.FullName 'rollback-case'
    $failRequest = 'DELETE custom-original'
    $failed = $false
    try { $null = & $migration -BaseUrl $origin -Apply -ClientsClosed -JournalDirectory $secondJournal }
    catch { $failed = $_.Exception.Message -like 'Favorites DELETE failed*' }
    Assert-True $failed 'A failing DELETE did not stop the operation.'
    $failRequest = ''
    $result = & $migration -BaseUrl $origin -Rollback -ClientsClosed -JournalDirectory $secondJournal
    Assert-True ($result.Mode -eq 'rolledBack' -and $server.SetEquals([string[]]@('custom-original', $seed[0]))) 'Rollback did not restore original membership.'
    'Favorites migration mock checks passed.'
} finally {
    $env:TC_BACKEND_AUTH_TOKEN = $oldToken
    foreach ($case in @('resume-case', 'rollback-case')) {
        $caseDirectory = Join-Path $sandbox.FullName $case
        foreach ($name in @('state.json', 'operation.lock')) {
            $file = Join-Path $caseDirectory $name
            if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file }
        }
        if (Test-Path -LiteralPath $caseDirectory -PathType Container) { [IO.Directory]::Delete($caseDirectory) }
    }
    $sandbox.Delete()
}

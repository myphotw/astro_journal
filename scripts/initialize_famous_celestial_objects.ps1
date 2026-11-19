#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Preview')]
param(
    [Parameter(Mandatory)]
    [uri] $BaseUrl,
    [Parameter(Mandatory, ParameterSetName = 'Apply')]
    [switch] $Apply,
    [Parameter(Mandatory, ParameterSetName = 'Resume')]
    [switch] $Resume,
    [Parameter(Mandatory, ParameterSetName = 'Rollback')]
    [switch] $Rollback,
    [switch] $ClientsClosed,
    [switch] $ForbidRemovals,
    [string] $JournalDirectory = (Join-Path $env:LOCALAPPDATA 'AstroJournal\famous-catalog-v1')
)

$ErrorActionPreference = 'Stop'
if (-not $BaseUrl.IsAbsoluteUri -or $BaseUrl.Scheme -ne 'https' -or
    $BaseUrl.AbsolutePath -ne '/' -or $BaseUrl.Query -or
    $BaseUrl.Fragment -or $BaseUrl.UserInfo) {
    throw 'Specify the verified HTTPS origin only (no path, query, or credentials).'
}

$origin = $BaseUrl.GetLeftPart([UriPartial]::Authority)
$endpoint = "$origin/api/astro/catalog-favorites"
$journal = Join-Path $JournalDirectory 'state.json'
$mutating = $Apply -or $Resume -or $Rollback
$seedPath = Join-Path $PSScriptRoot 'famous_celestial_objects_initial_ids.json'
$target = @(Get-Content -LiteralPath $seedPath -Raw | ConvertFrom-Json)
$ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($id in $target) {
    if ($id -isnot [string] -or $id -notmatch '^[a-zA-Z0-9_-]+$' -or
        -not $ids.Add($id)) { throw 'Invalid or duplicate seed ID.' }
}
if ($ids.Count -ne 317) { throw 'The audit seed must contain exactly 317 IDs.' }
$seedHash = (Get-FileHash -LiteralPath $seedPath -Algorithm SHA256).Hash

function Save-Journal {
    $temporary = Join-Path $JournalDirectory ([IO.Path]::GetRandomFileName())
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $state -Depth 8))
    [IO.File]::Move($temporary, $journal, $true)
}

function Send-FavoriteRequest([string] $Method, [string] $Id = '') {
    $uri = $endpoint
    $argsForRequest = @{
        Method = $Method; Headers = $authHeaders; TimeoutSec = 15
        MaximumRedirection = 0; ErrorAction = 'Stop'
    }
    if ($Method -eq 'POST') {
        $argsForRequest.ContentType = 'application/json'
        $argsForRequest.Body = @{catalog_object_id = $Id} | ConvertTo-Json -Compress
    } elseif ($Method -eq 'DELETE') {
        $uri += '/' + [uri]::EscapeDataString($Id)
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            if ($Method -ne 'GET') { Start-Sleep -Milliseconds 150 }
            $reply = Invoke-WebRequest -Uri $uri @argsForRequest
            try { $result = ConvertFrom-Json -InputObject $reply.Content -NoEnumerate }
            catch { throw [FormatException]::new('Invalid JSON response.') }
            if ($Method -eq 'GET') {
                if ($result -isnot [array]) { throw [FormatException]::new('Expected a list.') }
                return ,$result
            }
            if ($result.catalog_object_id -cne $Id -or
                ($Method -eq 'DELETE' -and $result.deleted -isnot [bool])) {
                throw [FormatException]::new('Unexpected mutation response.')
            }
            return
        } catch {
            $response = $_.Exception.Response
            $status = if ($response) { [int]$response.StatusCode } else { 0 }
            $retryable = $_.Exception -isnot [FormatException] -and
                ($status -in @(0, 408, 429) -or $status -ge 500)
            if (-not $retryable -or $attempt -eq 3) {
                $reason = if ($status) {
                    "HTTP $status"
                } elseif ($_.Exception -is [System.Net.Http.HttpRequestException] -and
                          $_.Exception.PSObject.Properties['HttpRequestError']) {
                    $_.Exception.HttpRequestError
                } else {
                    $_.Exception.GetType().Name
                }
                throw "Favorites $Method failed ($reason). Inspect the journal before continuing."
            }
            $delay = [Math]::Pow(2, $attempt)
            if ($status -eq 429 -and $response.Headers.RetryAfter) {
                $retryAfter = $response.Headers.RetryAfter
                if ($retryAfter.Delta) { $delay = [Math]::Max($delay, $retryAfter.Delta.TotalSeconds) }
                if ($retryAfter.Date) { $delay = [Math]::Max($delay, ($retryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds) }
            }
            if ($delay -gt 60) { throw 'Server requires a longer delay; resume later.' }
            Start-Sleep -Seconds ([Math]::Ceiling($delay))
        }
    }
}

function Get-IdSet($Rows) {
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $Rows) {
        if ($row.catalog_object_id -isnot [string] -or
            [string]::IsNullOrWhiteSpace($row.catalog_object_id) -or
            -not $set.Add($row.catalog_object_id)) {
            throw 'Invalid or duplicate ID in Favorites response.'
        }
    }
    return ,$set
}

function Get-ServerIds { return ,(Get-IdSet (Send-FavoriteRequest 'GET')) }

function Assert-KnownIds($Actual) {
    if (-not $Actual.IsSubsetOf($known)) {
        throw 'Unexpected IDs appeared after backup; stop and review concurrent changes.'
    }
}

function Set-Membership($Desired, $Actual) {
    Assert-KnownIds $Actual
    if ($ForbidRemovals -and -not $Actual.IsSubsetOf($Desired)) {
        throw 'Removals are forbidden; existing membership differs from the preview.'
    }
    $added = 0
    foreach ($id in $Desired) {
        if (-not $Actual.Contains($id)) {
            Send-FavoriteRequest 'POST' $id
            $added++
            if ($added % 25 -eq 0) { Write-Verbose "Registered $added missing IDs." }
        }
    }
    $afterAdd = Get-ServerIds
    Assert-KnownIds $afterAdd
    if (-not $Desired.IsSubsetOf($afterAdd)) {
        throw 'Not all required IDs are present; no deletions were started in this pass.'
    }
    if ($ForbidRemovals -and -not $afterAdd.IsSubsetOf($Desired)) {
        throw 'Removals are forbidden; existing membership changed during registration.'
    }
    foreach ($id in $afterAdd) {
        if (-not $Desired.Contains($id)) { Send-FavoriteRequest 'DELETE' $id }
    }
    if (-not (Get-ServerIds).SetEquals($Desired)) {
        throw 'Final Favorites verification failed.'
    }
}

if ($mutating -and -not $ClientsClosed) {
    throw 'Close all AstroJournal clients and pass -ClientsClosed while they remain closed.'
}
$token = $env:TC_BACKEND_AUTH_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    $secure = Read-Host 'TC-Backend token' -AsSecureString
    $token = ConvertFrom-SecureString -SecureString $secure -AsPlainText
}
if ([string]::IsNullOrWhiteSpace($token)) { throw 'Authentication token required.' }
$authHeaders = @{Authorization = "Bearer $token"; Accept = 'application/json'}
$lock = $null
try {
    if (-not $mutating) {
        $current = Get-ServerIds
        $missing = @($target | Where-Object { -not $current.Contains($_) })
        $extra = @($current | Where-Object { -not $ids.Contains($_) })
        [pscustomobject]@{
            Origin = $origin; Mode = 'Preview'; Current = $current.Count
            Target = $ids.Count; Adds = $missing.Count; Removes = $extra.Count
            JournalExists = (Test-Path -LiteralPath $journal)
        }
        return
    }

    New-Item -ItemType Directory -Path $JournalDirectory -Force | Out-Null
    $lock = [IO.File]::Open((Join-Path $JournalDirectory 'operation.lock'),
        [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    if (Test-Path -LiteralPath $journal) {
        $state = Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json -AsHashtable
        if ($state.phase -in @('completed', 'rolledBack')) {
            throw "Migration is closed ($($state.phase)); no writes made."
        }
        if ($Apply) { throw 'An unfinished journal exists; explicitly resume or roll back.' }
        if ($state.origin -cne $origin -or $state.seedHash -cne $seedHash -or
            -not $state.Contains('original')) {
            throw 'Origin, seed, or journal does not match the original operation.'
        }
        if ($Resume -and $state.phase -ne 'inProgress') {
            throw 'Rollback already started; continue with -Rollback.'
        }
    } else {
        if (-not $Apply) { throw 'No unfinished journal was found.' }
        $originalRows = Send-FavoriteRequest 'GET'
        $originalBeforeWrite = Get-IdSet $originalRows
        if ($ForbidRemovals -and -not $originalBeforeWrite.IsSubsetOf($ids)) {
            throw 'Removals are forbidden; existing membership differs from the preview.'
        }
        $state = @{
            origin = $origin; seedHash = $seedHash; phase = 'inProgress'
            original = @($originalRows)
        }
        Save-Journal
    }

    $original = Get-IdSet $state.original
    $known = [System.Collections.Generic.HashSet[string]]::new($original, [StringComparer]::Ordinal)
    $known.UnionWith($ids)
    if ($Rollback) {
        $state.phase = 'rollingBack'
        Save-Journal
        Set-Membership $original (Get-ServerIds)
        $state.phase = 'rolledBack'
    } else {
        Set-Membership $ids (Get-ServerIds)
        $state.phase = 'completed'
    }
    $state.verifiedAt = [DateTimeOffset]::UtcNow.ToString('o')
    Save-Journal
    [pscustomobject]@{
        Origin = $origin; Mode = $state.phase
        Verified = $(if ($Rollback) { $original.Count } else { $ids.Count })
        Journal = $journal
    }
} finally {
    if ($lock) { $lock.Dispose() }
    $authHeaders.Clear()
    $token = $null
}

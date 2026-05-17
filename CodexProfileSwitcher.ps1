<#
Codex Profile Switcher for Windows
Local-only utility. It switches the active Codex authentication by backing up/restoring auth files in %USERPROFILE%\.codex.
No credential/token display. Live usage refresh sends tokens only as HTTPS authorization headers.
Automatically closes Codex before replacing or clearing active auth files.
#>

param(
    [ValidateSet("", "StartEmptyProfile", "SwitchProfile", "SaveActive", "RenameProfile", "DeleteProfile")]
    [string]$Operation = "",
    [string]$ProfileName = "",
    [string]$TargetProfile = "",
    [string]$ResultFile = "",
    [string]$ErrorFile = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$CodexHome = Join-Path $env:USERPROFILE ".codex"
$ProfilesRoot = Join-Path $env:USERPROFILE ".codex-profiles"
$ActiveFile = Join-Path $ProfilesRoot ".active_profile.txt"
$OnboardingFile = Join-Path $ProfilesRoot ".onboarding_complete"
$LogFile = Join-Path $ProfilesRoot "switcher.log"
$ReservedProfileNames = @("_backups")
$AuthFileNames = @("auth.json", "cap_sid")
$UsageSnapshotFileName = "usage-limits.json"
$ChatGptBackendApi = "https://chatgpt.com/backend-api"
$ChatGptUsageEndpoint = "https://chatgpt.com/backend-api/wham/usage"
$ChatGptAuthIssuer = "https://auth.openai.com"
$ChatGptClientId = "app_EMoamEEZ73f0CkXaXp7hrann"
$CodexUserAgent = "codex-cli/1.0.0"
$AppName = "Codex Profile Switcher"
$HeaderText = "$AppName by A.R.V"
$CompanyName = "Agentic Revenue Vision"
$WindowTitle = "$AppName - $CompanyName"

function Ensure-Dirs {
    if (!(Test-Path $ProfilesRoot)) { New-Item -ItemType Directory -Path $ProfilesRoot | Out-Null }
}

function Write-Log($Message) {
    try {
        Ensure-Dirs
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "[$stamp] $Message"
    } catch {
        # Logging must never make a completed profile operation look failed.
    }
}

function Sanitize-ProfileName($Name) {
    $clean = ($Name -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { throw "Profile name cannot be empty." }
    if ($ReservedProfileNames -contains $clean) { throw "'$clean' is reserved and cannot be used as a profile name." }
    return $clean
}

function Get-AuthFileCount($Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return 0 }

    $count = 0
    foreach ($fileName in $AuthFileNames) {
        if (Test-Path (Join-Path $Path $fileName)) { $count++ }
    }
    return $count
}

function HasAuthFiles($Path) {
    return (Get-AuthFileCount $Path) -gt 0
}

function Clear-AuthFilesInPath($Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return }

    foreach ($fileName in $AuthFileNames) {
        $authPath = Join-Path $Path $fileName
        if (Test-Path $authPath) {
            Remove-Item -LiteralPath $authPath -Force
        }
    }
}

function Test-ProfileFolderExists($Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    try {
        $profilePath = Get-ProfilePath $Name
        return (Test-Path $profilePath)
    } catch {
        return $false
    }
}

function Get-ActiveProfile {
    if (Test-Path $ActiveFile) {
        $name = (Get-Content $ActiveFile -Raw).Trim()
        if ($name) {
            try {
                $safe = Sanitize-ProfileName $name
                if (Test-ProfileFolderExists $safe) { return $safe }
                Write-Log "Ignored missing active profile folder '$safe'."
            } catch {
                Write-Log "Ignored invalid active profile '$name': $($_.Exception.Message)"
            }
        }
    }
    if (Test-ProfileFolderExists "Default") { return "Default" }
    return ""
}

function Set-ActiveProfile($Name) {
    Ensure-Dirs
    $safe = Sanitize-ProfileName $Name
    Set-Content -Path $ActiveFile -Value $safe -Encoding UTF8
    Write-Log "Set active profile to '$safe'."
}

function Get-ProfilePath($Name) {
    $safe = Sanitize-ProfileName $Name
    return Join-Path $ProfilesRoot $safe
}

function Get-Profiles {
    Ensure-Dirs
    Get-ChildItem -Path $ProfilesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike ".*" -and $ReservedProfileNames -notcontains $_.Name } |
        Select-Object -ExpandProperty Name |
        Sort-Object
}

function Get-ProfilesWithAuth {
    @(Get-Profiles) | Where-Object { HasAuthFiles (Get-ProfilePath $_) }
}

function ConvertFrom-Base64Url($Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }

    $base64 = $Value.Replace("-", "+").Replace("_", "/")
    switch ($base64.Length % 4) {
        2 { $base64 += "==" }
        3 { $base64 += "=" }
        1 { return "" }
    }

    try {
        return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
    } catch {
        return ""
    }
}

function Get-ProfileEmail($Name) {
    try {
        $profilePath = Get-ProfilePath $Name
        $authPath = Join-Path $profilePath "auth.json"
        if (!(Test-Path $authPath)) { return "" }

        $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
        $idToken = [string]$auth.tokens.id_token
        if ([string]::IsNullOrWhiteSpace($idToken)) { return "" }

        $parts = $idToken -split "\."
        if ($parts.Count -lt 2) { return "" }

        $payloadJson = ConvertFrom-Base64Url $parts[1]
        if ([string]::IsNullOrWhiteSpace($payloadJson)) { return "" }

        $payload = $payloadJson | ConvertFrom-Json
        $email = [string]$payload.email
        if ($email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $email }
    } catch {
        Write-Log "Could not read profile email for '$Name': $($_.Exception.Message)"
    }

    return ""
}

function Get-JwtPayloadClaims($Token) {
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }

    $parts = $Token -split "\."
    if ($parts.Count -lt 2) { return $null }

    $payloadJson = ConvertFrom-Base64Url $parts[1]
    if ([string]::IsNullOrWhiteSpace($payloadJson)) { return $null }

    try {
        return ($payloadJson | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-ChatGptAccountIdFromClaims($Claims) {
    if ($null -eq $Claims) { return "" }

    $authProperty = $Claims.PSObject.Properties["https://api.openai.com/auth"]
    if ($null -ne $authProperty -and $null -ne $authProperty.Value) {
        $claimAccountId = [string]$authProperty.Value.chatgpt_account_id
        if (![string]::IsNullOrWhiteSpace($claimAccountId)) { return $claimAccountId }
    }

    return ""
}

function Test-JwtExpiredOrNearExpiry($Token) {
    $claims = Get-JwtPayloadClaims $Token
    if ($null -eq $claims -or $null -eq $claims.exp) { return $false }

    try {
        $expiresAt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$claims.exp)
        return ($expiresAt -le [DateTimeOffset]::UtcNow.AddSeconds(60))
    } catch {
        return $false
    }
}

function Get-ProfileAuthTokens($Name) {
    try {
        $authPath = Join-Path (Get-ProfilePath $Name) "auth.json"
        if (!(Test-Path $authPath)) { return $null }

        $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
        if ($null -eq $auth.tokens) { return $null }

        $idToken = [string]$auth.tokens.id_token
        $accessToken = [string]$auth.tokens.access_token
        $refreshToken = [string]$auth.tokens.refresh_token
        if ([string]::IsNullOrWhiteSpace($accessToken) -and [string]::IsNullOrWhiteSpace($refreshToken)) { return $null }

        $claims = Get-JwtPayloadClaims $idToken
        $accountId = [string]$auth.tokens.account_id
        if ([string]::IsNullOrWhiteSpace($accountId)) { $accountId = Get-ChatGptAccountIdFromClaims $claims }

        return [pscustomobject]@{
            AuthPath = $authPath
            IdToken = $idToken
            AccessToken = $accessToken
            RefreshToken = $refreshToken
            AccountId = $accountId
        }
    } catch {
        Write-Log "Could not read usage auth for '$Name': $($_.Exception.Message)"
        return $null
    }
}

function Invoke-ChatGptTokenRefresh($RefreshToken) {
    if ([string]::IsNullOrWhiteSpace($RefreshToken)) { throw "Missing refresh token." }

    $body = "grant_type=refresh_token&refresh_token=$([uri]::EscapeDataString($RefreshToken))&client_id=$([uri]::EscapeDataString($ChatGptClientId))"
    return Invoke-RestMethod -Method Post -Uri "$ChatGptAuthIssuer/oauth/token" -ContentType "application/x-www-form-urlencoded" -Body $body -TimeoutSec 20
}

function Update-ProfileAuthTokens($Name, $CurrentTokens, $RefreshResponse) {
    if ($null -eq $RefreshResponse -or [string]::IsNullOrWhiteSpace([string]$RefreshResponse.access_token)) {
        throw "Token refresh did not return an access token."
    }

    $authPath = $CurrentTokens.AuthPath
    $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
    $nextIdToken = if (![string]::IsNullOrWhiteSpace([string]$RefreshResponse.id_token)) { [string]$RefreshResponse.id_token } else { $CurrentTokens.IdToken }
    $nextRefreshToken = if (![string]::IsNullOrWhiteSpace([string]$RefreshResponse.refresh_token)) { [string]$RefreshResponse.refresh_token } else { $CurrentTokens.RefreshToken }
    $nextAccountId = Get-ChatGptAccountIdFromClaims (Get-JwtPayloadClaims $nextIdToken)
    if ([string]::IsNullOrWhiteSpace($nextAccountId)) { $nextAccountId = $CurrentTokens.AccountId }

    $auth.tokens.id_token = $nextIdToken
    $auth.tokens.access_token = [string]$RefreshResponse.access_token
    $auth.tokens.refresh_token = $nextRefreshToken
    if (![string]::IsNullOrWhiteSpace($nextAccountId)) {
        if ($null -eq $auth.tokens.PSObject.Properties["account_id"]) {
            $auth.tokens | Add-Member -NotePropertyName "account_id" -NotePropertyValue $nextAccountId
        } else {
            $auth.tokens.account_id = $nextAccountId
        }
    }
    if ($null -ne $auth.PSObject.Properties["last_refresh"]) {
        $auth.last_refresh = (Get-Date).ToUniversalTime().ToString("o")
    }

    $auth | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $authPath -Encoding UTF8

    if ($Name -eq (Get-ActiveProfile)) {
        if (!(Test-Path $CodexHome)) { New-Item -ItemType Directory -Path $CodexHome | Out-Null }
        Copy-Item -LiteralPath $authPath -Destination (Join-Path $CodexHome "auth.json") -Force
    }

    return (Get-ProfileAuthTokens $Name)
}

function Invoke-ChatGptUsageRequest($AccessToken, $AccountId) {
    if ([string]::IsNullOrWhiteSpace($AccessToken)) { throw "Missing access token." }

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "User-Agent" = $CodexUserAgent
    }
    if (![string]::IsNullOrWhiteSpace($AccountId)) {
        $headers["chatgpt-account-id"] = $AccountId
    }

    return Invoke-RestMethod -Method Get -Uri $ChatGptUsageEndpoint -Headers $headers -TimeoutSec 20
}

function Test-IsUnauthorizedError($ErrorRecord) {
    try {
        return ([int]$ErrorRecord.Exception.Response.StatusCode -eq 401)
    } catch {
        return $false
    }
}

function Convert-UsagePayloadToRateLimits($Payload) {
    if ($null -eq $Payload -or $null -eq $Payload.rate_limit) { return $null }

    $credits = 0
    if ($null -ne $Payload.credits) {
        if ($null -ne $Payload.credits.balance) { $credits = $Payload.credits.balance }
        elseif ($Payload.credits.unlimited) { $credits = "Unlimited" }
    }

    return [pscustomobject]@{
        primary = $Payload.rate_limit.primary_window
        secondary = $Payload.rate_limit.secondary_window
        credits = $credits
    }
}

function Get-LiveProfileUsage($ProfileName) {
    if ([string]::IsNullOrWhiteSpace($ProfileName)) { return $null }

    try {
        $tokens = Get-ProfileAuthTokens $ProfileName
        if ($null -eq $tokens) { return $null }

        if (Test-JwtExpiredOrNearExpiry $tokens.AccessToken) {
            $tokens = Update-ProfileAuthTokens $ProfileName $tokens (Invoke-ChatGptTokenRefresh $tokens.RefreshToken)
        }

        try {
            $payload = Invoke-ChatGptUsageRequest $tokens.AccessToken $tokens.AccountId
        } catch {
            if (!(Test-IsUnauthorizedError $_) -or [string]::IsNullOrWhiteSpace($tokens.RefreshToken)) { throw }
            $tokens = Update-ProfileAuthTokens $ProfileName $tokens (Invoke-ChatGptTokenRefresh $tokens.RefreshToken)
            $payload = Invoke-ChatGptUsageRequest $tokens.AccessToken $tokens.AccountId
        }

        $rateLimits = Convert-UsagePayloadToRateLimits $payload
        if ($null -eq $rateLimits) { return $null }

        $usage = New-UsageSnapshot "live:$ProfileName" (Get-Date) $rateLimits
        Save-UsageSnapshotToProfile $ProfileName $usage
        return $usage
    } catch {
        Write-Log "Could not refresh live usage for '$ProfileName': $($_.Exception.Message)"
        return $null
    }
}

function Refresh-AllProfileUsageSnapshots {
    foreach ($profile in @(Get-ProfilesWithAuth)) {
        [void](Get-LiveProfileUsage $profile)
    }
}

function Get-MaskedEmail($Email) {
    if ([string]::IsNullOrWhiteSpace($Email)) { return "" }

    if ($Email -match '^([^@]+)(@.+)$') {
        return (('*' * $matches[1].Length) + $matches[2])
    }

    return ('*' * $Email.Length)
}

function Format-DurationCompact($Seconds) {
    if ($Seconds -le 0) { return "0m" }

    $span = [TimeSpan]::FromSeconds($Seconds)
    $hours = [Math]::Floor($span.TotalHours)
    $minutes = $span.Minutes
    if ($hours -gt 0) { return ("{0}h {1}m" -f $hours, $minutes) }
    return ("{0}m" -f $minutes)
}

function New-UsageSnapshot($Source, $Timestamp, $RateLimits) {
    return [pscustomobject]@{
        Source = $Source
        Timestamp = $Timestamp
        RateLimits = $RateLimits
    }
}

function Get-UsageSnapshotPath($Name) {
    return Join-Path (Get-ProfilePath $Name) $UsageSnapshotFileName
}

function Read-UsageSnapshotFile($Path, $SourceLabel) {
    if (!(Test-Path $Path)) { return $null }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $rateLimits = if ($raw.rate_limits) { $raw.rate_limits } else { $raw }
        if (!($rateLimits.primary -or $rateLimits.secondary -or $rateLimits.primary_window -or $rateLimits.secondary_window)) {
            return $null
        }

        $timestamp = if ($raw.saved_at) { [DateTime]::Parse([string]$raw.saved_at).ToLocalTime() } else { (Get-Item -LiteralPath $Path).LastWriteTime }
        return (New-UsageSnapshot $SourceLabel $timestamp $rateLimits)
    } catch {
        Write-Log "Could not read usage snapshot '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Save-UsageSnapshotToProfile($Name, $Usage) {
    if ([string]::IsNullOrWhiteSpace($Name) -or $null -eq $Usage) { return }

    try {
        $profilePath = Get-ProfilePath $Name
        if (!(Test-Path $profilePath)) { return }

        $snapshot = [pscustomobject]@{
            saved_at = (Get-Date).ToString("o")
            source = $Usage.Source
            rate_limits = $Usage.RateLimits
        }
        $snapshot | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Get-UsageSnapshotPath $Name) -Encoding UTF8
    } catch {
        Write-Log "Could not save usage snapshot for '$Name': $($_.Exception.Message)"
    }
}

function Get-LatestCodexUsage($ProfileName) {
    $sessionRoot = Join-Path $CodexHome "sessions"
    $usageCache = Join-Path $CodexHome "usage-limits.json"
    $activeProfile = Get-ActiveProfile
    $snapshotUsage = if ($ProfileName) { Read-UsageSnapshotFile (Get-UsageSnapshotPath $ProfileName) "profile:$ProfileName" } else { $null }

    if ($ProfileName) {
        $liveUsage = Get-LiveProfileUsage $ProfileName
        if ($null -ne $liveUsage) { return $liveUsage }
    }

    if ($ProfileName -and $ProfileName -ne $activeProfile) {
        return $snapshotUsage
    }

    if (Test-Path $usageCache) {
        $cachedUsage = Read-UsageSnapshotFile $usageCache "active:usage-limits.json"
        if ($null -ne $cachedUsage) {
            if ($activeProfile) { Save-UsageSnapshotToProfile $activeProfile $cachedUsage }
            return $cachedUsage
        }
    }

    if (!(Test-Path $sessionRoot)) { return $null }

    $latest = $null
    $files = @(Get-ChildItem -Path $sessionRoot -Recurse -File -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 80)

    foreach ($file in $files) {
        try {
            foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                if ($line -notmatch '"rate_limits"') { continue }

                $entry = $line | ConvertFrom-Json
                $rateLimits = $entry.payload.rate_limits
                if ($null -eq $rateLimits) { continue }

                $timestamp = [DateTime]::Parse([string]$entry.timestamp).ToLocalTime()
                if ($null -eq $latest -or $timestamp -gt $latest.Timestamp) {
                    $latest = New-UsageSnapshot $file.FullName $timestamp $rateLimits
                }
            }
        } catch {
            Write-Log "Could not scan usage from '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    if ($activeProfile -and $null -ne $latest) { Save-UsageSnapshotToProfile $activeProfile $latest }
    if ($null -ne $latest) { return $latest }
    return $snapshotUsage
}

function Get-UsageWindowDisplay($Window) {
    if ($null -eq $Window) {
        return [pscustomobject]@{ LeftPercent = $null; ResetText = "No local usage data"; BarPercent = 0 }
    }

    $used = $null
    if ($null -ne $Window.used_percent) { $used = [double]$Window.used_percent }
    elseif ($null -ne $Window.usedPercent) { $used = [double]$Window.usedPercent }

    $left = if ($null -ne $used) { [Math]::Max(0, [Math]::Min(100, (100 - $used))) } else { $null }

    $resetText = "reset unknown"
    $resetValue = if ($null -ne $Window.resets_at) { $Window.resets_at } elseif ($null -ne $Window.reset_at) { $Window.reset_at } elseif ($null -ne $Window.resetsAt) { $Window.resetsAt } else { $null }
    if ($null -ne $resetValue) {
        try {
            $resetAt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$resetValue).LocalDateTime
            $seconds = [Math]::Max(0, ($resetAt - (Get-Date)).TotalSeconds)
            $resetText = "resets " + (Format-DurationCompact $seconds)
        } catch {
            $resetText = "reset unknown"
        }
    }

    $label = if ($null -ne $left) { ("{0}% left - {1}" -f ([Math]::Round($left)), $resetText) } else { "No local usage data" }
    return [pscustomobject]@{ LeftPercent = $left; ResetText = $label; BarPercent = $(if ($null -ne $left) { $left } else { 0 }) }
}

function Test-OnboardingComplete {
    return (Test-Path $OnboardingFile)
}

function Set-OnboardingComplete($Reason) {
    Ensure-Dirs
    Set-Content -Path $OnboardingFile -Value $Reason -Encoding UTF8
    Write-Log "Marked onboarding complete: $Reason"
}

function Copy-AuthFiles($Source, $Dest) {
    if (!(Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }
    Clear-AuthFilesInPath $Dest

    $copied = 0
    foreach ($fileName in $AuthFileNames) {
        $sourcePath = Join-Path $Source $fileName
        $destPath = Join-Path $Dest $fileName
        if (Test-Path $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
            $copied++
        }
    }

    return $copied
}

function Clear-ActiveAuthFiles {
    if (!(Test-Path $CodexHome)) { New-Item -ItemType Directory -Path $CodexHome | Out-Null }
    Clear-AuthFilesInPath $CodexHome
}

function Save-CurrentToProfile($Name) {
    Ensure-Dirs
    $safe = Sanitize-ProfileName $Name

    if (!(HasAuthFiles $CodexHome)) {
        Write-Log "No active auth files found. Profile '$safe' was not changed."
        return 0
    }

    $profilePath = Get-ProfilePath $safe
    if (!(Test-Path $profilePath)) { New-Item -ItemType Directory -Path $profilePath | Out-Null }

    $copied = Copy-AuthFiles $CodexHome $profilePath
    Write-Log "Saved $copied auth file(s) from active .codex to profile '$safe'."
    return $copied
}

function Restore-ProfileToCurrent($Name) {
    $safe = Sanitize-ProfileName $Name
    $profilePath = Get-ProfilePath $safe
    if (!(Test-Path $profilePath)) { throw "Profile not found: $safe" }
    if (!(Test-Path $CodexHome)) { New-Item -ItemType Directory -Path $CodexHome | Out-Null }

    Clear-ActiveAuthFiles
    $copied = Copy-AuthFiles $profilePath $CodexHome
    if ($copied -eq 0) { Write-Log "Profile '$safe' has no saved auth files. Active auth files were cleared." }
    Set-ActiveProfile $safe
    Write-Log "Restored $copied auth file(s) from profile '$safe' to active .codex."
}

function Start-EmptyProfile($Name) {
    Ensure-Dirs
    $safe = Sanitize-ProfileName $Name
    $profilePath = Get-ProfilePath $safe
    if (Test-Path $profilePath) { throw "Profile already exists: $safe" }

    $active = Get-ActiveProfile
    if ($active -and (HasAuthFiles $CodexHome)) {
        [void](Save-CurrentToProfile $active)
    } elseif ($active) {
        Write-Log "Skipped saving active profile '$active' because active .codex has no auth files."
    }

    New-Item -ItemType Directory -Path $profilePath | Out-Null
    Clear-ActiveAuthFiles
    Set-ActiveProfile $safe
    Write-Log "Started empty profile '$safe' for a new login."
}

function Remove-Profile($Name) {
    $safe = Sanitize-ProfileName $Name
    $active = Get-ActiveProfile
    if ($safe -eq $active) { throw "Cannot delete the active profile '$safe'. Switch to another profile first." }

    $profilePath = Get-ProfilePath $safe
    if (!(Test-Path $profilePath)) { throw "Profile not found: $safe" }

    Remove-Item -LiteralPath $profilePath -Recurse -Force
    Write-Log "Deleted profile '$safe'."
}

function Rename-Profile($OldName, $NewName) {
    $oldSafe = Sanitize-ProfileName $OldName
    $newSafe = Sanitize-ProfileName $NewName
    $active = Get-ActiveProfile

    if ($oldSafe -eq $active) { throw "Cannot rename the active profile '$oldSafe'. Switch to another profile first." }
    if ($oldSafe -eq $newSafe) { throw "New profile name must be different from the current name." }

    $oldPath = Get-ProfilePath $oldSafe
    if (!(Test-Path $oldPath)) { throw "Profile not found: $oldSafe" }
    if (Test-ProfileFolderExists $newSafe) { throw "Profile already exists: $newSafe" }

    $newPath = Get-ProfilePath $newSafe
    Move-Item -LiteralPath $oldPath -Destination $newPath
    Write-Log "Renamed profile '$oldSafe' to '$newSafe'."
}

function Get-CodexProcesses {
    # Official Windows app process is Codex.exe in current public reports/docs ecosystem.
    # Use exact process-name matching only to avoid closing unrelated windows whose title contains "Codex".
    return @(Get-Process -Name "Codex" -ErrorAction SilentlyContinue)
}

function Test-CodexProcessRunning {
    return @((Get-CodexProcesses)).Count -gt 0
}

function Close-CodexGracefully {
    $matches = Get-CodexProcesses
    if (@($matches).Count -eq 0) { return $true }

    foreach ($p in $matches) {
        try {
            if ($p.MainWindowHandle -ne 0) {
                [void]$p.CloseMainWindow()
                Write-Log "Requested graceful close for Codex process $($p.ProcessName) ($($p.Id))."
            }
        } catch {}
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (!(Test-CodexProcessRunning)) { return $true }
    }
    return $false
}

function Stop-CodexProcesses {
    $matches = Get-CodexProcesses
    foreach ($p in $matches) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Log "Force-stopped Codex process $($p.ProcessName) ($($p.Id))."
        } catch {
            Write-Log "Failed to force-stop Codex process $($p.ProcessName) ($($p.Id)): $($_.Exception.Message)"
        }
    }
}

function Close-CodexForOperation($OperationName) {
    if (!(Test-CodexProcessRunning)) { return }

    $ok = Close-CodexGracefully
    if ($ok) {
        Start-Sleep -Milliseconds 500
        return
    }

    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        Stop-CodexProcesses
        Start-Sleep -Milliseconds 750
        if (!(Test-CodexProcessRunning)) { return }
    }

    $remaining = Get-CodexProcesses |
        ForEach-Object { "$($_.ProcessName) ($($_.Id))" }

    throw "Could not close Codex automatically. Remaining process(es): $($remaining -join ', '). Close them from Task Manager, then try $OperationName again."
}

function Close-CodexForOnboardingSave($ProfileName) {
    if (!(Test-CodexProcessRunning)) { return }

    $ok = Close-CodexGracefully
    if ($ok) {
        Start-Sleep -Milliseconds 500
        return
    }

    $confirmed = Ask-YesNo "Codex did not close after a normal close request.`r`n`r`nForce-close Codex now and save profile '$ProfileName'?"
    if (!$confirmed) {
        throw "Codex is still running. The first profile was not saved."
    }

    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        Stop-CodexProcesses
        Start-Sleep -Milliseconds 750
        if (!(Test-CodexProcessRunning)) { return }
    }

    $remaining = Get-CodexProcesses |
        ForEach-Object { "$($_.ProcessName) ($($_.Id))" }

    throw "Could not close Codex automatically. Remaining process(es): $($remaining -join ', ')."
}

function Start-CodexApp {
    try {
        $app = Get-StartApps |
            Where-Object { $_.Name -eq "Codex" -or $_.AppID -like "*OpenAI.Codex*" } |
            Select-Object -First 1

        if ($app) {
            Start-Process ("shell:AppsFolder\" + $app.AppID)
            Write-Log "Re-opened Codex using Start menu app id '$($app.AppID)'."
            return $true
        }

        Start-Process "Codex.exe"
        Write-Log "Re-opened Codex using Codex.exe."
        return $true
    } catch {
        Write-Log "Could not re-open Codex automatically: $($_.Exception.Message)"
        return $false
    }
}

function Show-Info($Text) { [System.Windows.Forms.MessageBox]::Show($Text, $WindowTitle, 'OK', 'Information') | Out-Null }
function Show-Warn($Text) { [System.Windows.Forms.MessageBox]::Show($Text, $WindowTitle, 'OK', 'Warning') | Out-Null }
function Ask-YesNo($Text) { return ([System.Windows.Forms.MessageBox]::Show($Text, $WindowTitle, 'YesNo', 'Question') -eq 'Yes') }

function Confirm-DeleteProfile($Name) {
    $safe = Sanitize-ProfileName $Name

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - Confirm delete"
    $dialog.Size = New-Object System.Drawing.Size(470, 245)
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    $message = New-Object System.Windows.Forms.Label
    $message.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $message.AutoSize = $false
    $message.Size = New-Object System.Drawing.Size(410, 72)
    $message.Location = New-Object System.Drawing.Point(24, 20)
    $message.Text = "Delete profile '$safe'?`r`n`r`nThis removes only its saved auth profile folder. Type the profile name to confirm deletion."
    $dialog.Controls.Add($message)

    $confirmBox = New-Object System.Windows.Forms.TextBox
    $confirmBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $confirmBox.Location = New-Object System.Drawing.Point(28, 106)
    $confirmBox.Size = New-Object System.Drawing.Size(250, 28)
    $dialog.Controls.Add($confirmBox)

    $btnDeleteConfirm = New-Object System.Windows.Forms.Button
    $btnDeleteConfirm.Text = "Delete"
    $btnDeleteConfirm.Location = New-Object System.Drawing.Point(255, 156)
    $btnDeleteConfirm.Size = New-Object System.Drawing.Size(85, 32)
    $btnDeleteConfirm.Enabled = $false
    $dialog.Controls.Add($btnDeleteConfirm)

    $btnCancelDelete = New-Object System.Windows.Forms.Button
    $btnCancelDelete.Text = "Cancel"
    $btnCancelDelete.Location = New-Object System.Drawing.Point(350, 156)
    $btnCancelDelete.Size = New-Object System.Drawing.Size(85, 32)
    $dialog.Controls.Add($btnCancelDelete)

    $script:DeleteProfileConfirmed = $false
    $confirmBox.Add_TextChanged({ $btnDeleteConfirm.Enabled = (([string]$confirmBox.Text).Trim() -eq $safe) })
    $btnDeleteConfirm.Add_Click({
        $script:DeleteProfileConfirmed = $true
        $dialog.Close()
    })
    $btnCancelDelete.Add_Click({ $dialog.Close() })

    [void]$dialog.ShowDialog($form)
    return $script:DeleteProfileConfirmed
}

function Prompt-ForProfileName($Title, $Prompt, $InitialValue) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - $Title"
    $dialog.Size = New-Object System.Drawing.Size(460, 230)
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Prompt
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $label.AutoSize = $false
    $label.Size = New-Object System.Drawing.Size(395, 48)
    $label.Location = New-Object System.Drawing.Point(24, 22)
    $dialog.Controls.Add($label)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $nameBox.Location = New-Object System.Drawing.Point(28, 82)
    $nameBox.Size = New-Object System.Drawing.Size(260, 28)
    $nameBox.Text = $InitialValue
    if ($InitialValue) { $nameBox.SelectAll() }
    $dialog.Controls.Add($nameBox)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(252, 140)
    $btnOk.Size = New-Object System.Drawing.Size(80, 32)
    $btnOk.Enabled = -not [string]::IsNullOrWhiteSpace($nameBox.Text)
    $dialog.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(342, 140)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 32)
    $dialog.Controls.Add($btnCancel)

    $script:PromptedProfileName = ""
    $nameBox.Add_TextChanged({ $btnOk.Enabled = -not [string]::IsNullOrWhiteSpace($nameBox.Text) })
    $btnOk.Add_Click({
        try {
            $script:PromptedProfileName = Sanitize-ProfileName $nameBox.Text
            $dialog.Close()
        } catch {
            Show-Warn $_.Exception.Message
        }
    })
    $btnCancel.Add_Click({ $dialog.Close() })

    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel
    [void]$dialog.ShowDialog($form)
    return $script:PromptedProfileName
}

function Should-ShowOnboarding {
    if (Test-OnboardingComplete) { return $false }
    return @((Get-ProfilesWithAuth)).Count -eq 0
}

function Show-OnboardingConsent {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - Setup consent"
    $dialog.Size = New-Object System.Drawing.Size(560, 395)
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "Before first-time setup"
    $heading.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(22, 20)
    $dialog.Controls.Add($heading)

    $message = New-Object System.Windows.Forms.Label
    $message.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $message.AutoSize = $false
    $message.Size = New-Object System.Drawing.Size(500, 160)
    $message.Location = New-Object System.Drawing.Point(24, 62)
    $message.Text = "Codex Profile Switcher changes accounts by saving and restoring local Codex auth files in your user folders.`r`n`r`nUse this app only with accounts you own, purchased, or are otherwise authorized to use. Do not use this app to share accounts, bypass account restrictions, or violate OpenAI's or any other service provider's terms, policies, or applicable law.`r`n`r`nYou are responsible for how you use this app. Agentic Revenue Vision provides this utility for lawful personal account switching only and is not responsible for misuse by users."
    $dialog.Controls.Add($message)

    $consentBox = New-Object System.Windows.Forms.CheckBox
    $consentBox.Text = "I understand Codex may close during setup."
    $consentBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $consentBox.AutoSize = $true
    $consentBox.Location = New-Object System.Drawing.Point(28, 235)
    $dialog.Controls.Add($consentBox)

    $termsBox = New-Object System.Windows.Forms.CheckBox
    $termsBox.Text = "I agree to use this app only with accounts I am authorized to use."
    $termsBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $termsBox.AutoSize = $true
    $termsBox.Location = New-Object System.Drawing.Point(28, 263)
    $dialog.Controls.Add($termsBox)

    $btnContinue = New-Object System.Windows.Forms.Button
    $btnContinue.Text = "Continue"
    $btnContinue.Location = New-Object System.Drawing.Point(325, 315)
    $btnContinue.Size = New-Object System.Drawing.Size(90, 32)
    $btnContinue.Enabled = $false
    $dialog.Controls.Add($btnContinue)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Exit"
    $btnCancel.Location = New-Object System.Drawing.Point(428, 315)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 32)
    $dialog.Controls.Add($btnCancel)

    $script:OnboardingConsentAccepted = $false
    $updateContinueButton = {
        $btnContinue.Enabled = ($consentBox.Checked -and $termsBox.Checked)
    }
    $consentBox.Add_CheckedChanged($updateContinueButton)
    $termsBox.Add_CheckedChanged($updateContinueButton)
    $btnContinue.Add_Click({
        $script:OnboardingConsentAccepted = $true
        $dialog.Close()
    })
    $btnCancel.Add_Click({ $dialog.Close() })

    [void]$dialog.ShowDialog()
    return $script:OnboardingConsentAccepted
}

function Show-OnboardingWizard {
    if (!(Show-OnboardingConsent)) { return $false }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$WindowTitle - First setup"
    $dialog.Size = New-Object System.Drawing.Size(500, 345)
    $dialog.StartPosition = "CenterScreen"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "First-time setup"
    $heading.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(22, 20)
    $dialog.Controls.Add($heading)

    $message = New-Object System.Windows.Forms.Label
    $message.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $message.AutoSize = $false
    $message.Size = New-Object System.Drawing.Size(440, 85)
    $message.Location = New-Object System.Drawing.Point(24, 62)
    $dialog.Controls.Add($message)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = "First profile name"
    $profileLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $profileLabel.AutoSize = $true
    $profileLabel.Location = New-Object System.Drawing.Point(25, 154)
    $dialog.Controls.Add($profileLabel)

    $profileNameBox = New-Object System.Windows.Forms.TextBox
    $profileNameBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $profileNameBox.Text = "Default"
    $profileNameBox.Location = New-Object System.Drawing.Point(28, 178)
    $profileNameBox.Size = New-Object System.Drawing.Size(250, 28)
    $profileNameBox.SelectAll()
    $dialog.Controls.Add($profileNameBox)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Default is only a suggestion; rename it if helpful."
    $hint.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $hint.AutoSize = $true
    $hint.Location = New-Object System.Drawing.Point(28, 211)
    $dialog.Controls.Add($hint)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save first profile"
    $btnSave.Location = New-Object System.Drawing.Point(28, 252)
    $btnSave.Size = New-Object System.Drawing.Size(135, 32)
    $dialog.Controls.Add($btnSave)

    $btnOpenCodex = New-Object System.Windows.Forms.Button
    $btnOpenCodex.Text = "Open Codex"
    $btnOpenCodex.Location = New-Object System.Drawing.Point(28, 252)
    $btnOpenCodex.Size = New-Object System.Drawing.Size(105, 32)
    $dialog.Controls.Add($btnOpenCodex)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh"
    $btnRefresh.Location = New-Object System.Drawing.Point(145, 252)
    $btnRefresh.Size = New-Object System.Drawing.Size(95, 32)
    $dialog.Controls.Add($btnRefresh)

    $btnSkip = New-Object System.Windows.Forms.Button
    $btnSkip.Text = "Skip setup"
    $btnSkip.Location = New-Object System.Drawing.Point(252, 252)
    $btnSkip.Size = New-Object System.Drawing.Size(105, 32)
    $dialog.Controls.Add($btnSkip)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(369, 252)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 32)
    $dialog.Controls.Add($btnCancel)

    $script:OnboardingCanContinue = $false

    $refreshOnboarding = {
        $hasAuth = HasAuthFiles $CodexHome
        $runningText = if (Test-CodexProcessRunning) { "Codex is currently running." } else { "Codex is not running." }

        $profileLabel.Visible = $hasAuth
        $profileNameBox.Visible = $hasAuth
        $hint.Visible = $hasAuth
        $btnSave.Visible = $hasAuth
        $btnCancel.Visible = $hasAuth
        $btnOpenCodex.Visible = -not $hasAuth
        $btnSkip.Visible = -not $hasAuth

        if ($hasAuth) {
            $message.Text = "Codex auth files were found in your active .codex folder. Name this first saved profile, then save it before using the switcher.`r`n`r`n$runningText"
        } else {
            $message.Text = "No Codex auth files were found yet. Open Codex and sign in, then return here and refresh. You can also skip setup and create a profile later.`r`n`r`n$runningText"
        }
    }

    $btnSave.Add_Click({
        try {
            $name = Sanitize-ProfileName $profileNameBox.Text
            if (Test-ProfileFolderExists $name) {
                Show-Warn "Profile '$name' already exists. Choose a different name for the first profile."
                return
            }
            if (!(HasAuthFiles $CodexHome)) {
                Show-Warn "No Codex auth files were found. Open Codex, sign in, then refresh."
                & $refreshOnboarding
                return
            }

            if (Test-CodexProcessRunning) {
                $confirmed = Ask-YesNo "Codex is running. To save this first profile, Codex must be closed first.`r`n`r`nClose Codex now and save profile '$name'?"
                if (!$confirmed) { return }
                Close-CodexForOnboardingSave $name
            }

            $copied = Save-CurrentToProfile $name
            if ($copied -lt 1) {
                throw "No auth files were saved. Open Codex, sign in, then refresh onboarding."
            }

            Set-ActiveProfile $name
            Set-OnboardingComplete "saved first profile '$name'"
            Show-Info "Saved first profile: $name"
            if (Ask-YesNo "Open Codex now?") { [void](Start-CodexApp) }
            $script:OnboardingCanContinue = $true
            $dialog.Close()
        } catch {
            Show-Warn $_.Exception.Message
            & $refreshOnboarding
        }
    })

    $btnOpenCodex.Add_Click({ [void](Start-CodexApp) })
    $btnRefresh.Add_Click({ & $refreshOnboarding })
    $btnSkip.Add_Click({
        Set-OnboardingComplete "skipped setup"
        $script:OnboardingCanContinue = $true
        $dialog.Close()
    })
    $btnCancel.Add_Click({ $dialog.Close() })

    & $refreshOnboarding
    [void]$dialog.ShowDialog()
    return $script:OnboardingCanContinue
}

function Write-OperationResult($Text) {
    if ($ResultFile) {
        Set-Content -LiteralPath $ResultFile -Value $Text -Encoding UTF8
    } else {
        Write-Output $Text
    }
}

function Write-OperationError($Text) {
    if ($ErrorFile) {
        Set-Content -LiteralPath $ErrorFile -Value $Text -Encoding UTF8
    } else {
        [Console]::Error.WriteLine($Text)
    }
}

if ($Operation) {
    try {
        Ensure-Dirs
        switch ($Operation) {
            "StartEmptyProfile" {
                $name = Sanitize-ProfileName $ProfileName
                Close-CodexForOperation "starting a new login profile"
                Start-EmptyProfile $name
                Write-OperationResult "Started new login profile: $name`r`nOpen Codex and log in. Your existing projects and chat sessions stay in the shared .codex folder. After login completes, click 'Save active login' to capture this profile's auth."
            }
            "SwitchProfile" {
                $target = Sanitize-ProfileName $TargetProfile
                Close-CodexForOperation "switching profiles"
                $active = Get-ActiveProfile
                if ($active -and (HasAuthFiles $CodexHome)) {
                    [void](Save-CurrentToProfile $active)
                } elseif ($active) {
                    Write-Log "Skipped saving active profile '$active' before switch because active .codex has no auth files."
                }
                [void](Restore-ProfileToCurrent $target)
                $opened = Start-CodexApp
                if ($opened) {
                    Write-OperationResult "Switched to profile: $target`r`nCodex was re-opened."
                } else {
                    Write-OperationResult "Switched to profile: $target`r`nCodex could not be re-opened automatically. Open it manually."
                }
            }
            "SaveActive" {
                $active = Get-ActiveProfile
                if (!$active) { throw "No active profile is saved yet. Complete onboarding or prepare a new account login first." }
                $copied = Save-CurrentToProfile $active
                if ($copied -lt 1) { throw "No Codex auth files were found. Open Codex, sign in, then try again." }
                Write-OperationResult "Saved current auth files into active profile: $active"
            }
            "RenameProfile" {
                $target = Sanitize-ProfileName $TargetProfile
                $name = Sanitize-ProfileName $ProfileName
                Rename-Profile $target $name
                Write-OperationResult "Renamed profile '$target' to '$name'"
            }
            "DeleteProfile" {
                $target = Sanitize-ProfileName $TargetProfile
                Remove-Profile $target
                Write-OperationResult "Deleted profile: $target"
            }
        }
        exit 0
    } catch {
        Write-OperationError $_.Exception.Message
        exit 1
    }
}

Ensure-Dirs
if (Should-ShowOnboarding) {
    if (!(Show-OnboardingWizard)) { exit 0 }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $WindowTitle
$form.ClientSize = New-Object System.Drawing.Size(600, 560)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$script:IsDarkMode = $false
$ColorCanvas = $null
$ColorPanel = $null
$ColorRaised = $null
$ColorInk = $null
$ColorSecondary = $null
$ColorBorder = $null
$ColorUsageTrack = $null
$ColorEmail = $null
$ColorDisabledFill = $null
$ColorDisabledText = $null
$ColorDangerFill = $null
$ColorDangerHover = $null
$ColorSecondaryDown = $null
$ColorBlue = [System.Drawing.Color]::FromArgb(11, 102, 216)
$ColorBluePressed = [System.Drawing.Color]::FromArgb(0, 79, 172)
$ColorBlueTint = $null
$ColorDanger = [System.Drawing.Color]::FromArgb(180, 35, 24)

function Set-ThemeColors($DarkMode) {
    if ($DarkMode) {
        Set-Variable -Name ColorCanvas -Scope Script -Value ([System.Drawing.Color]::FromArgb(13, 20, 31))
        Set-Variable -Name ColorPanel -Scope Script -Value ([System.Drawing.Color]::FromArgb(22, 32, 46))
        Set-Variable -Name ColorRaised -Scope Script -Value ([System.Drawing.Color]::FromArgb(27, 39, 56))
        Set-Variable -Name ColorInk -Scope Script -Value ([System.Drawing.Color]::FromArgb(233, 240, 248))
        Set-Variable -Name ColorSecondary -Scope Script -Value ([System.Drawing.Color]::FromArgb(156, 171, 190))
        Set-Variable -Name ColorBorder -Scope Script -Value ([System.Drawing.Color]::FromArgb(55, 70, 91))
        Set-Variable -Name ColorBlueTint -Scope Script -Value ([System.Drawing.Color]::FromArgb(28, 58, 99))
        Set-Variable -Name ColorUsageTrack -Scope Script -Value ([System.Drawing.Color]::FromArgb(43, 56, 73))
        Set-Variable -Name ColorEmail -Scope Script -Value ([System.Drawing.Color]::FromArgb(185, 201, 220))
        Set-Variable -Name ColorDisabledFill -Scope Script -Value ([System.Drawing.Color]::FromArgb(30, 42, 58))
        Set-Variable -Name ColorDisabledText -Scope Script -Value ([System.Drawing.Color]::FromArgb(116, 131, 150))
        Set-Variable -Name ColorDangerFill -Scope Script -Value ([System.Drawing.Color]::FromArgb(57, 31, 35))
        Set-Variable -Name ColorDangerHover -Scope Script -Value ([System.Drawing.Color]::FromArgb(76, 37, 43))
        Set-Variable -Name ColorSecondaryDown -Scope Script -Value ([System.Drawing.Color]::FromArgb(35, 49, 68))
    } else {
        Set-Variable -Name ColorCanvas -Scope Script -Value ([System.Drawing.Color]::FromArgb(246, 248, 251))
        Set-Variable -Name ColorPanel -Scope Script -Value ([System.Drawing.Color]::White)
        Set-Variable -Name ColorRaised -Scope Script -Value ([System.Drawing.Color]::FromArgb(249, 251, 254))
        Set-Variable -Name ColorInk -Scope Script -Value ([System.Drawing.Color]::FromArgb(16, 32, 51))
        Set-Variable -Name ColorSecondary -Scope Script -Value ([System.Drawing.Color]::FromArgb(93, 107, 122))
        Set-Variable -Name ColorBorder -Scope Script -Value ([System.Drawing.Color]::FromArgb(215, 224, 234))
        Set-Variable -Name ColorBlueTint -Scope Script -Value ([System.Drawing.Color]::FromArgb(230, 240, 255))
        Set-Variable -Name ColorUsageTrack -Scope Script -Value ([System.Drawing.Color]::FromArgb(230, 238, 248))
        Set-Variable -Name ColorEmail -Scope Script -Value ([System.Drawing.Color]::FromArgb(75, 94, 114))
        Set-Variable -Name ColorDisabledFill -Scope Script -Value ([System.Drawing.Color]::FromArgb(242, 245, 248))
        Set-Variable -Name ColorDisabledText -Scope Script -Value ([System.Drawing.Color]::FromArgb(150, 160, 170))
        Set-Variable -Name ColorDangerFill -Scope Script -Value ([System.Drawing.Color]::FromArgb(255, 232, 232))
        Set-Variable -Name ColorDangerHover -Scope Script -Value ([System.Drawing.Color]::FromArgb(255, 245, 245))
        Set-Variable -Name ColorSecondaryDown -Scope Script -Value ([System.Drawing.Color]::FromArgb(232, 238, 246))
    }
}

Set-ThemeColors $false
$form.BackColor = $ColorCanvas

function Add-BorderPaint($Control, $Radius, $BorderColor, $FillColor) {
    $Control.Tag = @{
        Radius = $Radius
        BorderColor = $BorderColor
        FillColor = $FillColor
    }
    $Control.Add_Paint({
        param($sender, $eventArgs)

        $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $style = $sender.Tag
        $path = New-RoundedRectanglePath $sender.Width $sender.Height ([int]$style["Radius"])
        $fillBrush = New-Object System.Drawing.SolidBrush($style["FillColor"])
        $borderPen = New-Object System.Drawing.Pen($style["BorderColor"])
        $eventArgs.Graphics.FillPath($fillBrush, $path)
        $eventArgs.Graphics.DrawPath($borderPen, $path)
        $fillBrush.Dispose()
        $borderPen.Dispose()
        $path.Dispose()
    })
}

function Update-BorderPaintStyle($Control, $Radius, $BorderColor, $FillColor) {
    $Control.Tag = @{
        Radius = $Radius
        BorderColor = $BorderColor
        FillColor = $FillColor
    }
    $Control.BackColor = $FillColor
    $Control.Invalidate()
}

$title = New-Object System.Windows.Forms.Label
$title.Text = $HeaderText
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.ForeColor = $ColorInk
$title.Location = New-Object System.Drawing.Point(24, 22)
$form.Controls.Add($title)

$modePanel = New-Object System.Windows.Forms.Panel
$modePanel.Location = New-Object System.Drawing.Point(454, 21)
$modePanel.Size = New-Object System.Drawing.Size(122, 32)
$modePanel.BackColor = $ColorPanel
Add-BorderPaint $modePanel 6 $ColorBorder $ColorPanel
$form.Controls.Add($modePanel)

$modeLight = New-Object System.Windows.Forms.Label
$modeLight.Text = "Light"
$modeLight.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$modeLight.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$modeLight.ForeColor = [System.Drawing.Color]::White
$modeLight.BackColor = $ColorBlue
$modeLight.Location = New-Object System.Drawing.Point(4, 4)
$modeLight.Size = New-Object System.Drawing.Size(56, 24)
$modePanel.Controls.Add($modeLight)

$modeDark = New-Object System.Windows.Forms.Label
$modeDark.Text = "Dark"
$modeDark.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$modeDark.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$modeDark.ForeColor = $ColorSecondary
$modeDark.BackColor = $ColorPanel
$modeDark.Location = New-Object System.Drawing.Point(62, 4)
$modeDark.Size = New-Object System.Drawing.Size(56, 24)
$modePanel.Controls.Add($modeDark)

$script:HideProfileEmails = $false
$hideEmailsToggle = New-Object System.Windows.Forms.CheckBox
$hideEmailsToggle.Text = "Hide emails"
$hideEmailsToggle.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$hideEmailsToggle.ForeColor = $ColorSecondary
$hideEmailsToggle.AutoSize = $true
$hideEmailsToggle.Location = New-Object System.Drawing.Point(38, 415)
$form.Controls.Add($hideEmailsToggle)
$hideEmailsToggle.Add_CheckedChanged({
    $script:HideProfileEmails = $hideEmailsToggle.Checked
    $list.Invalidate()
})

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(24, 67)
$statusPanel.Size = New-Object System.Drawing.Size(552, 50)
$statusPanel.BackColor = $ColorRaised
Add-BorderPaint $statusPanel 8 $ColorBorder $ColorRaised
$form.Controls.Add($statusPanel)

$activeCaption = New-Object System.Windows.Forms.Label
$activeCaption.Text = "Active profile"
$activeCaption.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$activeCaption.ForeColor = $ColorSecondary
$activeCaption.Location = New-Object System.Drawing.Point(14, 8)
$activeCaption.Size = New-Object System.Drawing.Size(116, 16)
$statusPanel.Controls.Add($activeCaption)

$activeValue = New-Object System.Windows.Forms.Label
$activeValue.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$activeValue.ForeColor = $ColorInk
$activeValue.Location = New-Object System.Drawing.Point(14, 25)
$activeValue.Size = New-Object System.Drawing.Size(116, 18)
$statusPanel.Controls.Add($activeValue)

$authCaption = New-Object System.Windows.Forms.Label
$authCaption.Text = "Saved auth files"
$authCaption.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$authCaption.ForeColor = $ColorSecondary
$authCaption.Location = New-Object System.Drawing.Point(160, 8)
$authCaption.Size = New-Object System.Drawing.Size(116, 16)
$statusPanel.Controls.Add($authCaption)

$authValue = New-Object System.Windows.Forms.Label
$authValue.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$authValue.ForeColor = $ColorInk
$authValue.Location = New-Object System.Drawing.Point(160, 25)
$authValue.Size = New-Object System.Drawing.Size(116, 18)
$statusPanel.Controls.Add($authValue)

$codexCaption = New-Object System.Windows.Forms.Label
$codexCaption.Text = "Codex state"
$codexCaption.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$codexCaption.ForeColor = $ColorSecondary
$codexCaption.Location = New-Object System.Drawing.Point(306, 8)
$codexCaption.Size = New-Object System.Drawing.Size(210, 16)
$statusPanel.Controls.Add($codexCaption)

$codexValue = New-Object System.Windows.Forms.Label
$codexValue.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$codexValue.ForeColor = $ColorInk
$codexValue.Location = New-Object System.Drawing.Point(306, 25)
$codexValue.Size = New-Object System.Drawing.Size(225, 18)
$codexValue.AutoEllipsis = $true
$statusPanel.Controls.Add($codexValue)

$profilesLabel = New-Object System.Windows.Forms.Label
$profilesLabel.Text = "Profiles"
$profilesLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$profilesLabel.AutoSize = $true
$profilesLabel.ForeColor = $ColorInk
$profilesLabel.Location = New-Object System.Drawing.Point(24, 137)
$form.Controls.Add($profilesLabel)

$actionsLabel = New-Object System.Windows.Forms.Label
$actionsLabel.Text = "Actions"
$actionsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$actionsLabel.AutoSize = $true
$actionsLabel.ForeColor = $ColorInk
$actionsLabel.Location = New-Object System.Drawing.Point(378, 137)
$form.Controls.Add($actionsLabel)

function New-RoundedRectanglePath($Width, $Height, $Radius) {
    $width = [Math]::Max(1, [int]$Width)
    $height = [Math]::Max(1, [int]$Height)
    $safeRadius = [Math]::Min([int]$Radius, [Math]::Min([int]($width / 2), [int]($height / 2)))
    $diameter = $safeRadius * 2

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($safeRadius -le 0) {
        $path.AddRectangle((New-Object System.Drawing.Rectangle(0, 0, $width, $height)))
        return $path
    } else {
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
        $path.CloseFigure()
    }

    return $path
}

$profilePanel = New-Object System.Windows.Forms.Panel
$profilePanel.Location = New-Object System.Drawing.Point(24, 160)
$profilePanel.Size = New-Object System.Drawing.Size(318, 250)
$profilePanel.BackColor = $ColorPanel
Add-BorderPaint $profilePanel 8 $ColorBorder $ColorPanel
$form.Controls.Add($profilePanel)

$list = New-Object System.Windows.Forms.ListBox
$list.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$list.Location = New-Object System.Drawing.Point(1, 1)
$list.Size = New-Object System.Drawing.Size(316, 248)
$list.BackColor = $ColorPanel
$list.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$list.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$list.ItemHeight = 74
$profilePanel.Controls.Add($list)

$list.Add_DrawItem({
    param($sender, $eventArgs)

    if ($eventArgs.Index -lt 0) { return }

    $profileName = [string]$sender.Items[$eventArgs.Index]
    $activeProfile = Get-ActiveProfile
    $isActive = ($profileName -eq $activeProfile)
    $hasSavedLogin = HasAuthFiles (Get-ProfilePath $profileName)
    $isSelected = (($eventArgs.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected)

    $backColor = if ($isActive) { $ColorBlue } elseif ($isSelected) { $ColorBlueTint } else { $sender.BackColor }
    $nameColor = if ($isActive) { [System.Drawing.Color]::White } else { $ColorInk }
    $statusColor = if ($isActive) { [System.Drawing.Color]::FromArgb(231, 241, 255) } else { $ColorSecondary }
    $emailColor = if ($isActive) { [System.Drawing.Color]::FromArgb(231, 241, 255) } else { $ColorEmail }
    $statusText = if ($isActive) { "Active profile" } elseif ($hasSavedLogin) { "Saved login" } else { "No saved login" }
    $email = Get-ProfileEmail $profileName
    $emailText = if ([string]::IsNullOrWhiteSpace($email)) { "Email unavailable" } elseif ($script:HideProfileEmails) { Get-MaskedEmail $email } else { $email }

    $bounds = $eventArgs.Bounds
    $rowRect = New-Object System.Drawing.Rectangle(($bounds.Left + 8), ($bounds.Top + 6), ($bounds.Width - 16), ($bounds.Height - 12))
    $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rowPath = New-RoundedRectanglePath $rowRect.Width $rowRect.Height 6
    $eventArgs.Graphics.TranslateTransform($rowRect.Left, $rowRect.Top)
    $fillBrush = New-Object System.Drawing.SolidBrush($backColor)
    $eventArgs.Graphics.FillPath($fillBrush, $rowPath)
    $fillBrush.Dispose()
    if (-not $isActive) {
        $rowPen = New-Object System.Drawing.Pen($ColorBorder)
        $eventArgs.Graphics.DrawPath($rowPen, $rowPath)
        $rowPen.Dispose()
    }
    $eventArgs.Graphics.ResetTransform()
    $rowPath.Dispose()

    $left = $bounds.Left + 20
    $nameRect = New-Object System.Drawing.Rectangle($left, ($bounds.Top + 11), ($bounds.Width - 40), 18)
    $emailRect = New-Object System.Drawing.Rectangle($left, ($bounds.Top + 31), ($bounds.Width - 40), 16)
    $statusRect = New-Object System.Drawing.Rectangle($left, ($bounds.Top + 49), ($bounds.Width - 40), 16)

    $nameFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $emailFont = New-Object System.Drawing.Font("Segoe UI", 8)
    $statusFont = New-Object System.Drawing.Font("Segoe UI", 8)
    [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $profileName, $nameFont, $nameRect, $nameColor, [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $emailText, $emailFont, $emailRect, $emailColor, [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $statusText, $statusFont, $statusRect, $statusColor, [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    $nameFont.Dispose()
    $emailFont.Dispose()
    $statusFont.Dispose()

    $eventArgs.DrawFocusRectangle()
})

function Set-ActionButtonStyle($Button, $Kind) {
    $Button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.UseVisualStyleBackColor = $false
    $Button.BackColor = $ColorPanel
    $Button.ForeColor = $ColorInk
    $Button.Tag = @{ Kind = $Kind; State = "normal" }
    $Button.Add_MouseEnter({ param($sender, $eventArgs) $sender.Tag["State"] = "hover"; $sender.Invalidate() })
    $Button.Add_MouseLeave({ param($sender, $eventArgs) $sender.Tag["State"] = "normal"; $sender.Invalidate() })
    $Button.Add_MouseDown({ param($sender, $eventArgs) $sender.Tag["State"] = "down"; $sender.Invalidate() })
    $Button.Add_MouseUp({ param($sender, $eventArgs) $sender.Tag["State"] = "hover"; $sender.Invalidate() })
    $Button.Add_EnabledChanged({ param($sender, $eventArgs) $sender.Invalidate() })
    $Button.Add_Paint({
        param($sender, $eventArgs)

        $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $path = New-RoundedRectanglePath $sender.Width $sender.Height 6
        $kind = [string]$sender.Tag["Kind"]
        $state = [string]$sender.Tag["State"]

        if (-not $sender.Enabled -and $kind -eq "primary") {
            $fillColor = $ColorBlue
            $borderColor = $ColorBlue
            $textColor = [System.Drawing.Color]::White
        } elseif (-not $sender.Enabled) {
            $fillColor = $ColorDisabledFill
            $borderColor = $ColorBorder
            $textColor = $ColorDisabledText
        } elseif ($kind -eq "primary") {
            $fillColor = if ($state -eq "down") { $ColorBluePressed } else { $ColorBlue }
            $borderColor = $fillColor
            $textColor = [System.Drawing.Color]::White
        } elseif ($kind -eq "danger") {
            $fillColor = if ($state -eq "down") { $ColorDangerFill } elseif ($state -eq "hover") { $ColorDangerHover } else { $ColorPanel }
            $borderColor = if ($state -eq "normal") { $ColorBorder } else { $ColorDanger }
            $textColor = $ColorDanger
        } else {
            $fillColor = if ($state -eq "down") { $ColorSecondaryDown } elseif ($state -eq "hover") { $ColorRaised } else { $ColorPanel }
            $borderColor = $ColorBorder
            $textColor = $ColorInk
        }

        $fillBrush = New-Object System.Drawing.SolidBrush($fillColor)
        $borderPen = New-Object System.Drawing.Pen($borderColor)
        $eventArgs.Graphics.FillPath($fillBrush, $path)
        $eventArgs.Graphics.DrawPath($borderPen, $path)
        $fillBrush.Dispose()
        $borderPen.Dispose()
        $path.Dispose()

        [System.Windows.Forms.TextRenderer]::DrawText(
            $eventArgs.Graphics,
            $sender.Text,
            $sender.Font,
            $rect,
            $textColor,
            [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
        )
    })
}

$btnNewLogin = New-Object System.Windows.Forms.Button
$btnNewLogin.Text = "Add account"
$btnNewLogin.Location = New-Object System.Drawing.Point(378, 216)
$btnNewLogin.Size = New-Object System.Drawing.Size(198, 38)
Set-ActionButtonStyle $btnNewLogin "secondary"
$form.Controls.Add($btnNewLogin)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save active login"
$btnSave.Location = New-Object System.Drawing.Point(378, 264)
$btnSave.Size = New-Object System.Drawing.Size(198, 38)
Set-ActionButtonStyle $btnSave "secondary"
$form.Controls.Add($btnSave)

$btnSwitch = New-Object System.Windows.Forms.Button
$btnSwitch.Text = "Switch profile"
$btnSwitch.Location = New-Object System.Drawing.Point(378, 160)
$btnSwitch.Size = New-Object System.Drawing.Size(198, 42)
Set-ActionButtonStyle $btnSwitch "primary"
$form.Controls.Add($btnSwitch)

$btnRename = New-Object System.Windows.Forms.Button
$btnRename.Text = "Rename"
$btnRename.Location = New-Object System.Drawing.Point(378, 312)
$btnRename.Size = New-Object System.Drawing.Size(94, 36)
Set-ActionButtonStyle $btnRename "secondary"
$form.Controls.Add($btnRename)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "Delete"
$btnDelete.Location = New-Object System.Drawing.Point(482, 312)
$btnDelete.Size = New-Object System.Drawing.Size(94, 36)
Set-ActionButtonStyle $btnDelete "danger"
$form.Controls.Add($btnDelete)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(378, 360)
$btnRefresh.Size = New-Object System.Drawing.Size(198, 36)
Set-ActionButtonStyle $btnRefresh "secondary"
$form.Controls.Add($btnRefresh)

$usagePanel = New-Object System.Windows.Forms.Panel
$usagePanel.Location = New-Object System.Drawing.Point(24, 442)
$usagePanel.Size = New-Object System.Drawing.Size(552, 88)
$usagePanel.BackColor = $ColorPanel
Add-BorderPaint $usagePanel 8 $ColorBorder $ColorPanel
$form.Controls.Add($usagePanel)
$usageTracks = New-Object System.Collections.ArrayList

function Add-UsageLabel($Text, $X, $Y, $Width, $Color, $Bold) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 8, $style)
    $label.ForeColor = $Color
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 16)
    $label.AutoEllipsis = $true
    $usagePanel.Controls.Add($label)
    return $label
}

function Add-UsageBar($Y, $Percent) {
    $track = New-Object System.Windows.Forms.Panel
    $track.Location = New-Object System.Drawing.Point(10, $Y)
    $track.Size = New-Object System.Drawing.Size(532, 6)
    $track.BackColor = $ColorUsageTrack
    $usagePanel.Controls.Add($track)
    [void]$usageTracks.Add($track)

    $fill = New-Object System.Windows.Forms.Panel
    $fill.Location = New-Object System.Drawing.Point(0, 0)
    $fill.Size = New-Object System.Drawing.Size(([int]([Math]::Max(0, [Math]::Min(100, $Percent)) * 532 / 100)), 6)
    $fill.BackColor = $ColorBlue
    $track.Controls.Add($fill)
    return $fill
}

$usageText = $ColorInk
$usageMuted = $ColorSecondary
$limit5hLabel = Add-UsageLabel "5h Limit (5h)" 10 8 170 $usageText $false
$limit5hValue = Add-UsageLabel "No local usage data" 300 8 242 $usageText $false
$limit5hValue.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$limit5hBar = Add-UsageBar 25 0
$weeklyLabel = Add-UsageLabel "Weekly Limit (7d)" 10 38 170 $usageText $false
$weeklyValue = Add-UsageLabel "No local usage data" 300 38 242 $usageText $false
$weeklyValue.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$weeklyBar = Add-UsageBar 55 0
$creditsValue = Add-UsageLabel "Credits: 0" 10 68 170 $usageText $false
$lastUpdatedValue = Add-UsageLabel "Last updated: Never" 300 68 242 $usageMuted $false
$lastUpdatedValue.TextAlign = [System.Drawing.ContentAlignment]::TopRight

$tutorialLink = New-Object System.Windows.Forms.LinkLabel
$tutorialLink.Text = "Watch tutorial"
$tutorialLink.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$tutorialLink.Location = New-Object System.Drawing.Point(378, 536)
$tutorialLink.Size = New-Object System.Drawing.Size(198, 16)
$tutorialLink.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$tutorialLink.LinkColor = $ColorBlue
$tutorialLink.ActiveLinkColor = $ColorBluePressed
$tutorialLink.VisitedLinkColor = $ColorBlue
$tutorialLink.BackColor = $ColorCanvas
$tutorialLink.Add_LinkClicked({
    try {
        Start-Process "https://youtu.be/JA8C-SHFS50"
    } catch {
        Show-Warn "Could not open tutorial video: $($_.Exception.Message)"
    }
})
$form.Controls.Add($tutorialLink)

function Apply-Theme($DarkMode) {
    $script:IsDarkMode = [bool]$DarkMode
    Set-ThemeColors $script:IsDarkMode

    $form.BackColor = $ColorCanvas
    $title.ForeColor = $ColorInk
    $profilesLabel.ForeColor = $ColorInk
    $actionsLabel.ForeColor = $ColorInk
    $tutorialLink.LinkColor = $ColorBlue
    $tutorialLink.ActiveLinkColor = $ColorBluePressed
    $tutorialLink.VisitedLinkColor = $ColorBlue
    $tutorialLink.BackColor = $ColorCanvas
    $hideEmailsToggle.ForeColor = $ColorSecondary
    $hideEmailsToggle.BackColor = $ColorCanvas

    Update-BorderPaintStyle $modePanel 6 $ColorBorder $ColorPanel
    if ($script:IsDarkMode) {
        $modeLight.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $modeLight.ForeColor = $ColorSecondary
        $modeLight.BackColor = $ColorPanel
        $modeDark.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $modeDark.ForeColor = [System.Drawing.Color]::White
        $modeDark.BackColor = $ColorBlue
    } else {
        $modeLight.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $modeLight.ForeColor = [System.Drawing.Color]::White
        $modeLight.BackColor = $ColorBlue
        $modeDark.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $modeDark.ForeColor = $ColorSecondary
        $modeDark.BackColor = $ColorPanel
    }

    Update-BorderPaintStyle $statusPanel 8 $ColorBorder $ColorRaised
    foreach ($caption in @($activeCaption, $authCaption, $codexCaption)) { $caption.ForeColor = $ColorSecondary }
    foreach ($value in @($activeValue, $authValue, $codexValue)) { $value.ForeColor = $ColorInk }

    Update-BorderPaintStyle $profilePanel 8 $ColorBorder $ColorPanel
    $list.BackColor = $ColorPanel
    $list.ForeColor = $ColorInk

    foreach ($button in @($btnNewLogin, $btnSave, $btnSwitch, $btnRename, $btnDelete, $btnRefresh)) {
        $button.BackColor = $ColorPanel
        $button.ForeColor = $ColorInk
        $button.Invalidate()
    }

    Update-BorderPaintStyle $usagePanel 8 $ColorBorder $ColorPanel
    foreach ($label in @($limit5hLabel, $limit5hValue, $weeklyLabel, $weeklyValue, $creditsValue)) { $label.ForeColor = $ColorInk }
    $lastUpdatedValue.ForeColor = $ColorSecondary
    foreach ($track in $usageTracks) { $track.BackColor = $ColorUsageTrack }
    $limit5hBar.BackColor = $ColorBlue
    $weeklyBar.BackColor = $ColorBlue

    $list.Invalidate()
    $form.Invalidate($true)
}

$modeLight.Add_Click({ Apply-Theme $false })
$modeDark.Add_Click({ Apply-Theme $true })

function Update-UsagePanelForSelectedProfile {
    $selectedProfile = if ($list.SelectedItem -ne $null) { [string]$list.SelectedItem } else { Get-ActiveProfile }
    $usage = if ($selectedProfile) { Get-LatestCodexUsage $selectedProfile } else { $null }
    if ($null -ne $usage) {
        $primaryWindow = if ($usage.RateLimits.primary) { $usage.RateLimits.primary } elseif ($usage.RateLimits.primary_window) { $usage.RateLimits.primary_window } else { $null }
        $secondaryWindow = if ($usage.RateLimits.secondary) { $usage.RateLimits.secondary } elseif ($usage.RateLimits.secondary_window) { $usage.RateLimits.secondary_window } else { $null }
        $primary = Get-UsageWindowDisplay $primaryWindow
        $secondary = Get-UsageWindowDisplay $secondaryWindow
        $limit5hValue.Text = $primary.ResetText
        $weeklyValue.Text = $secondary.ResetText
        $limit5hBar.Width = [int]([Math]::Max(0, [Math]::Min(100, $primary.BarPercent)) * 532 / 100)
        $weeklyBar.Width = [int]([Math]::Max(0, [Math]::Min(100, $secondary.BarPercent)) * 532 / 100)
        $credits = if ($null -ne $usage.RateLimits.credits) { $usage.RateLimits.credits } else { 0 }
        $creditsValue.Text = "Credits: $credits"
        $lastUpdatedValue.Text = "Last updated: " + $usage.Timestamp.ToString("MMM d, h:mm tt")
    } else {
        $limit5hValue.Text = "No saved usage data"
        $weeklyValue.Text = "No saved usage data"
        $limit5hBar.Width = 0
        $weeklyBar.Width = 0
        $creditsValue.Text = "Credits: 0"
        $lastUpdatedValue.Text = "Last updated: Never"
    }
}

function Refresh-UI {
    $list.Items.Clear()
    $profiles = @(Get-Profiles)
    foreach ($p in $profiles) { [void]$list.Items.Add($p) }
    $active = Get-ActiveProfile
    if ($profiles -contains $active) { $list.SelectedItem = $active }
    $running = if (Test-CodexProcessRunning) { "Codex is running" } else { "Codex is not running" }
    $activeCaption.Text = "Active profile"
    $authCaption.Text = "Saved auth files"
    $codexCaption.Text = "Codex state"
    $activeValue.Text = if ($active) { $active } else { "None" }
    $authValue.Text = "None"
    if ($active) {
        $authCount = Get-AuthFileCount (Get-ProfilePath $active)
        $authValue.Text = if ($authCount -gt 0) { [string]$authCount } else { "None" }
    }
    $codexValue.Text = $running
    Update-UsagePanelForSelectedProfile
    Update-ActionButtonStates
}

function Update-SwitchButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnSwitch.Enabled = $false
        return
    }

    if ($list.SelectedItem -eq $null) {
        $btnSwitch.Enabled = $false
        return
    }

    $selected = [string]$list.SelectedItem
    $active = Get-ActiveProfile
    $btnSwitch.Enabled = ($selected -ne $active)
}

function Update-NewLoginButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnNewLogin.Enabled = $false
        return
    }

    $btnNewLogin.Enabled = $true
}

function Update-SaveButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnSave.Enabled = $false
        return
    }

    $btnSave.Enabled = -not [string]::IsNullOrWhiteSpace((Get-ActiveProfile))
}

function Update-RenameButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnRename.Enabled = $false
        return
    }

    if ($list.SelectedItem -eq $null) {
        $btnRename.Enabled = $false
        return
    }

    $selected = [string]$list.SelectedItem
    $active = Get-ActiveProfile
    $btnRename.Enabled = ($selected -ne $active)
}

function Update-DeleteButtonState {
    if ($script:CurrentOperationProcess -ne $null) {
        $btnDelete.Enabled = $false
        return
    }

    if ($list.SelectedItem -eq $null) {
        $btnDelete.Enabled = $false
        return
    }

    $selected = [string]$list.SelectedItem
    $active = Get-ActiveProfile
    $btnDelete.Enabled = ($selected -ne $active)
}

function Update-ActionButtonStates {
    Update-SwitchButtonState
    Update-NewLoginButtonState
    Update-SaveButtonState
    Update-RenameButtonState
    Update-DeleteButtonState
}

function Set-OperationControlsEnabled($Enabled) {
    foreach ($control in @($btnNewLogin, $btnSave, $btnSwitch, $btnRename, $btnDelete, $btnRefresh, $list)) {
        $control.Enabled = $Enabled
    }

    if ($Enabled) { Update-ActionButtonStates }
}

function Set-OperationStatus($OperationName, $StateText, $DetailText) {
    $activeCaption.Text = "Operation"
    $activeValue.Text = $OperationName
    $authCaption.Text = "State"
    $authValue.Text = $StateText
    $codexCaption.Text = "Detail"
    $codexValue.Text = $DetailText
}

function Quote-CommandLineArgument($Value) {
    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Read-TrimmedFile($Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return "" }

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return "" }

    return $content.Trim()
}

function Get-OperationLauncher {
    $currentProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $currentProcessName = [System.IO.Path]::GetFileName($currentProcessPath)
    $hostNames = @("powershell.exe", "powershell_ise.exe", "pwsh.exe")

    if ($hostNames -notcontains $currentProcessName.ToLowerInvariant()) {
        return @{
            FilePath = $currentProcessPath
            Arguments = @()
        }
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw "Could not determine script path for background operation."
    }

    return @{
        FilePath = "powershell.exe"
        Arguments = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", (Quote-CommandLineArgument $scriptPath)
        )
    }
}

function Get-CompletedProcessExitCode($Process) {
    try {
        $Process.Refresh()
        [void]$Process.WaitForExit(1000)
        return $Process.ExitCode
    } catch {
        return $null
    }
}

$script:CurrentOperationProcess = $null
$script:CurrentOperationName = ""
$script:CurrentOperationStartedAt = $null
$script:CurrentOperationOutput = ""
$script:CurrentOperationError = ""
$script:ClearProfileNameOnSuccess = $false

$operationTimer = New-Object System.Windows.Forms.Timer
$operationTimer.Interval = 500
$operationTimer.Add_Tick({
    try {
        if ($script:CurrentOperationProcess -eq $null) { return }

        if (-not $script:CurrentOperationProcess.HasExited) {
            $elapsed = [int]((Get-Date) - $script:CurrentOperationStartedAt).TotalSeconds
            Set-OperationStatus $script:CurrentOperationName "Running" "Elapsed: $elapsed seconds"
            return
        }

        $operationTimer.Stop()
        $exitCode = Get-CompletedProcessExitCode $script:CurrentOperationProcess
        $output = Read-TrimmedFile $script:CurrentOperationOutput
        $errorText = Read-TrimmedFile $script:CurrentOperationError

        Remove-Item -LiteralPath $script:CurrentOperationOutput, $script:CurrentOperationError -Force -ErrorAction SilentlyContinue

        $completedOperation = $script:CurrentOperationName
        $clearName = $script:ClearProfileNameOnSuccess
        $script:CurrentOperationProcess = $null
        $script:CurrentOperationName = ""
        $script:CurrentOperationStartedAt = $null
        $script:CurrentOperationOutput = ""
        $script:CurrentOperationError = ""
        $script:ClearProfileNameOnSuccess = $false

        Set-OperationControlsEnabled $true
        Refresh-UI

        $treatAsSuccess = ($exitCode -eq 0) -or ($output -and !$errorText)

        if ($treatAsSuccess) {
            if ($output) { Show-Info $output } else { Show-Info "$completedOperation completed." }
        } else {
            if (!$errorText) {
                if ($null -eq $exitCode) {
                    $errorText = "$completedOperation may have failed, but PowerShell did not report an exit code."
                } else {
                    $errorText = "$completedOperation failed with exit code $exitCode."
                }
            }
            Show-Warn $errorText
        }
    } catch {
        $operationTimer.Stop()
        $script:CurrentOperationProcess = $null
        $script:CurrentOperationName = ""
        $script:CurrentOperationStartedAt = $null
        Remove-Item -LiteralPath $script:CurrentOperationOutput, $script:CurrentOperationError -Force -ErrorAction SilentlyContinue
        $script:CurrentOperationOutput = ""
        $script:CurrentOperationError = ""
        $script:ClearProfileNameOnSuccess = $false
        Set-OperationControlsEnabled $true
        Refresh-UI
        Show-Warn "Operation status update failed: $($_.Exception.Message)"
    }
})

function Start-ProfileOperation($OperationName, $DisplayName, $Arguments, $ClearNameOnSuccess) {
    if ($script:CurrentOperationProcess -ne $null) {
        Show-Warn "Another operation is already running."
        return
    }

    $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-profile-switcher-" + [guid]::NewGuid().ToString("N") + ".out")
    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-profile-switcher-" + [guid]::NewGuid().ToString("N") + ".err")
    $launcher = Get-OperationLauncher

    $argList = @($launcher.Arguments) + @(
        "-Operation", (Quote-CommandLineArgument $OperationName),
        "-ResultFile", (Quote-CommandLineArgument $outFile),
        "-ErrorFile", (Quote-CommandLineArgument $errFile)
    )

    foreach ($key in $Arguments.Keys) {
        $argList += "-$key"
        $argList += (Quote-CommandLineArgument $Arguments[$key])
    }

    try {
        Set-OperationControlsEnabled $false
        Set-OperationStatus $DisplayName "Starting" "Background operation"
        $form.Refresh()

        $process = Start-Process -FilePath $launcher.FilePath -ArgumentList ($argList -join " ") -WindowStyle Hidden -PassThru

        $script:CurrentOperationProcess = $process
        $script:CurrentOperationName = $DisplayName
        $script:CurrentOperationStartedAt = Get-Date
        $script:CurrentOperationOutput = $outFile
        $script:CurrentOperationError = $errFile
        $script:ClearProfileNameOnSuccess = $ClearNameOnSuccess
        $operationTimer.Start()
    } catch {
        Set-OperationControlsEnabled $true
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
        Show-Warn $_.Exception.Message
        Refresh-UI
    }
}

$btnNewLogin.Add_Click({
    try {
        $name = Prompt-ForProfileName "Name new account profile" "Enter a name for the account you want to add." ""
        if (!$name) { return }
        if (Test-ProfileFolderExists $name) { Show-Warn "Profile '$name' already exists."; return }
        if (!(Ask-YesNo "Prepare new account login for '$name'?`r`n`r`nThis saves the current active auth profile, closes Codex, and clears only the active auth files so Codex can show the login screen.`r`n`r`nDo not use this if you only want to switch to an existing profile.")) { return }
        Start-ProfileOperation "StartEmptyProfile" "Preparing new account login '$name'" @{ ProfileName = $name } $true
    } catch { Show-Warn $_.Exception.Message }
})

$btnSwitch.Add_Click({
    try {
        if ($list.SelectedItem -eq $null) { Show-Warn "Select a profile first."; return }
        $target = [string]$list.SelectedItem
        if (!(HasAuthFiles (Get-ProfilePath $target))) {
            if (!(Ask-YesNo "Profile '$target' has no saved auth files. Switching to it will clear the active Codex auth files.`r`n`r`nSwitch anyway?")) { return }
        }
        $active = Get-ActiveProfile
        if ($target -eq $active) {
            Show-Info "Profile '$target' is already active."
            Update-SwitchButtonState
            return
        }
        Start-ProfileOperation "SwitchProfile" "Switching to profile '$target'" @{ TargetProfile = $target } $false
    } catch { Show-Warn $_.Exception.Message }
})

$btnRename.Add_Click({
    try {
        if ($list.SelectedItem -eq $null) { Show-Warn "Select a profile first."; return }
        $target = [string]$list.SelectedItem
        $active = Get-ActiveProfile
        if ($target -eq $active) { Show-Warn "Cannot rename the active profile. Switch to another profile first."; return }
        $name = Prompt-ForProfileName "Rename profile" "Enter a new name for profile '$target'." $target
        if (!$name) { return }
        if ($name -eq $target) { Show-Warn "New profile name must be different from the current name."; return }
        if (Test-ProfileFolderExists $name) { Show-Warn "Profile '$name' already exists."; return }
        Start-ProfileOperation "RenameProfile" "Renaming profile '$target'" @{ TargetProfile = $target; ProfileName = $name } $true
    } catch { Show-Warn $_.Exception.Message }
})

$btnSave.Add_Click({
    try {
        $active = Get-ActiveProfile
        if (!$active) { Show-Warn "No active profile is saved yet. Complete onboarding or prepare a new account login first."; return }
        Start-ProfileOperation "SaveActive" "Saving active profile '$active'" @{} $false
    } catch { Show-Warn $_.Exception.Message }
})

$btnDelete.Add_Click({
    try {
        if ($list.SelectedItem -eq $null) { Show-Warn "Select a profile first."; return }
        $target = [string]$list.SelectedItem
        if ($target -eq (Get-ActiveProfile)) { Show-Warn "Cannot delete the active profile. Switch to another profile first."; return }
        if (!(Confirm-DeleteProfile $target)) { return }
        Start-ProfileOperation "DeleteProfile" "Deleting profile '$target'" @{ TargetProfile = $target } $false
    } catch { Show-Warn $_.Exception.Message }
})

$btnRefresh.Add_Click({ Refresh-AllProfileUsageSnapshots; Refresh-UI })
$list.Add_SelectedIndexChanged({
    Update-UsagePanelForSelectedProfile
    Update-ActionButtonStates
})

Refresh-UI
[void]$form.ShowDialog()

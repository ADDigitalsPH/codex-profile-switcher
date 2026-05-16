<#
Codex Profile Switcher for Windows
Local-only utility. It switches the active Codex authentication by backing up/restoring auth files in %USERPROFILE%\.codex.
No credential/token display. No network calls. No external dependencies.
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
    $dialog.Size = New-Object System.Drawing.Size(500, 285)
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
    $message.Size = New-Object System.Drawing.Size(440, 95)
    $message.Location = New-Object System.Drawing.Point(24, 62)
    $message.Text = "Codex Profile Switcher changes accounts by saving and restoring local Codex auth files in your user folders.`r`n`r`nDuring setup, Codex may need to close automatically so auth files can be saved safely. You will be asked before Codex is closed."
    $dialog.Controls.Add($message)

    $consentBox = New-Object System.Windows.Forms.CheckBox
    $consentBox.Text = "I understand Codex may close during setup."
    $consentBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $consentBox.AutoSize = $true
    $consentBox.Location = New-Object System.Drawing.Point(28, 168)
    $dialog.Controls.Add($consentBox)

    $btnContinue = New-Object System.Windows.Forms.Button
    $btnContinue.Text = "Continue"
    $btnContinue.Location = New-Object System.Drawing.Point(265, 212)
    $btnContinue.Size = New-Object System.Drawing.Size(90, 32)
    $btnContinue.Enabled = $false
    $dialog.Controls.Add($btnContinue)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Exit"
    $btnCancel.Location = New-Object System.Drawing.Point(368, 212)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 32)
    $dialog.Controls.Add($btnCancel)

    $script:OnboardingConsentAccepted = $false
    $consentBox.Add_CheckedChanged({ $btnContinue.Enabled = $consentBox.Checked })
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
                Write-OperationResult "Started new login profile: $name`r`nOpen Codex and log in. Your existing projects and chat sessions stay in the shared .codex folder. After login completes, click 'Save current profile now' to capture this profile's auth."
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
$form.Size = New-Object System.Drawing.Size(560, 405)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

$title = New-Object System.Windows.Forms.Label
$title.Text = $HeaderText
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$status.AutoSize = $false
$status.Size = New-Object System.Drawing.Size(500, 40)
$status.Location = New-Object System.Drawing.Point(22, 58)
$form.Controls.Add($status)

$list = New-Object System.Windows.Forms.ListBox
$list.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$list.Location = New-Object System.Drawing.Point(25, 105)
$list.Size = New-Object System.Drawing.Size(250, 205)
$list.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$list.ItemHeight = 48
$form.Controls.Add($list)

$list.Add_DrawItem({
    param($sender, $eventArgs)

    if ($eventArgs.Index -lt 0) { return }

    $profileName = [string]$sender.Items[$eventArgs.Index]
    $activeProfile = Get-ActiveProfile
    $isActive = ($profileName -eq $activeProfile)
    $hasSavedLogin = HasAuthFiles (Get-ProfilePath $profileName)
    $isSelected = (($eventArgs.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected)

    $backColor = if ($isSelected) { [System.Drawing.SystemColors]::Highlight } else { $sender.BackColor }
    $nameColor = if ($isSelected) { [System.Drawing.SystemColors]::HighlightText } else { [System.Drawing.Color]::FromArgb(20, 20, 20) }
    $statusColor = if ($isSelected) { [System.Drawing.Color]::FromArgb(235, 245, 255) } else { [System.Drawing.Color]::FromArgb(75, 75, 75) }
    $statusText = if ($isActive) { "Active profile" } elseif ($hasSavedLogin) { "Saved login" } else { "No saved login" }

    $eventArgs.DrawBackground()

    $bounds = $eventArgs.Bounds
    $fillBrush = New-Object System.Drawing.SolidBrush($backColor)
    $eventArgs.Graphics.FillRectangle($fillBrush, $bounds)
    $fillBrush.Dispose()

    $left = $bounds.Left + 8
    $nameRect = New-Object System.Drawing.Rectangle($left, ($bounds.Top + 7), ($bounds.Width - 16), 20)
    $statusRect = New-Object System.Drawing.Rectangle($left, ($bounds.Top + 27), ($bounds.Width - 16), 16)

    $nameFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $statusFont = New-Object System.Drawing.Font("Segoe UI", 8)
    [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $profileName, $nameFont, $nameRect, $nameColor, [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $statusText, $statusFont, $statusRect, $statusColor, [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    $nameFont.Dispose()
    $statusFont.Dispose()

    if ($isActive) {
        $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 215))
        $eventArgs.Graphics.FillRectangle($accentBrush, $bounds.Left, ($bounds.Top + 6), 4, ($bounds.Height - 12))
        $accentBrush.Dispose()
    }

    $eventArgs.DrawFocusRectangle()
})

$btnNewLogin = New-Object System.Windows.Forms.Button
$btnNewLogin.Text = "Add account"
$btnNewLogin.Location = New-Object System.Drawing.Point(300, 105)
$btnNewLogin.Size = New-Object System.Drawing.Size(210, 34)
$form.Controls.Add($btnNewLogin)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save active login"
$btnSave.Location = New-Object System.Drawing.Point(300, 146)
$btnSave.Size = New-Object System.Drawing.Size(210, 34)
$form.Controls.Add($btnSave)

$btnSwitch = New-Object System.Windows.Forms.Button
$btnSwitch.Text = "Switch profile"
$btnSwitch.Location = New-Object System.Drawing.Point(300, 189)
$btnSwitch.Size = New-Object System.Drawing.Size(210, 38)
$btnSwitch.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnSwitch)

$btnRename = New-Object System.Windows.Forms.Button
$btnRename.Text = "Rename"
$btnRename.Location = New-Object System.Drawing.Point(300, 237)
$btnRename.Size = New-Object System.Drawing.Size(100, 34)
$form.Controls.Add($btnRename)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "Delete"
$btnDelete.Location = New-Object System.Drawing.Point(410, 237)
$btnDelete.Size = New-Object System.Drawing.Size(100, 34)
$form.Controls.Add($btnDelete)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(300, 279)
$btnRefresh.Size = New-Object System.Drawing.Size(210, 32)
$form.Controls.Add($btnRefresh)

function Refresh-UI {
    $list.Items.Clear()
    $profiles = @(Get-Profiles)
    foreach ($p in $profiles) { [void]$list.Items.Add($p) }
    $active = Get-ActiveProfile
    if ($profiles -contains $active) { $list.SelectedItem = $active }
    $running = if (Test-CodexProcessRunning) { "Codex appears to be running. Create/switch will auto-close it first." } else { "Codex does not appear to be running." }
    $activeText = if ($active) { "Active profile: $active" } else { "No active profile saved yet." }
    $authText = ""
    if ($active) {
        $authCount = Get-AuthFileCount (Get-ProfilePath $active)
        $authText = if ($authCount -gt 0) { "Saved auth files: $authCount" } else { "This profile has no saved auth yet." }
    }
    $detailText = if ($authText) { "$authText. $running" } else { $running }
    $status.Text = "$activeText`r`n$detailText"
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
            $status.Text = "$($script:CurrentOperationName) in progress...`r`nElapsed: $elapsed seconds. The window should remain responsive."
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
        $status.Text = "$DisplayName in progress...`r`nStarting background operation."
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

$btnRefresh.Add_Click({ Refresh-UI })
$list.Add_SelectedIndexChanged({ Update-ActionButtonStates })

Refresh-UI
[void]$form.ShowDialog()

<#
Codex Profile Switcher per-user installer.
Built into CodexProfileSwitcherSetup.exe with ps2exe embedded payload files.
#>

param(
    [switch]$Unattended
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$AppName = "Codex Profile Switcher"
$CompanyName = "Agentic Revenue Vision"
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA "Programs\Codex Profile Switcher"
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Codex Profile Switcher"
$DesktopShortcutPath = Join-Path ([Environment]::GetFolderPath("DesktopDirectory")) "Codex Profile Switcher.lnk"
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexProfileSwitcher"
$PayloadDir = Join-Path $env:TEMP "CodexProfileSwitcherPayload"

function Show-InstallerError($Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "$AppName Setup", "OK", "Error") | Out-Null
}

function Show-InstallerInfo($Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "$AppName Setup", "OK", "Information") | Out-Null
}

function Get-PayloadPath($Name) {
    $path = Join-Path $PayloadDir $Name
    if (!(Test-Path -LiteralPath $path)) {
        throw "Installer payload is missing: $Name"
    }
    return $path
}

function Copy-PayloadFile($Name, $InstallDir) {
    Copy-Item -LiteralPath (Get-PayloadPath $Name) -Destination (Join-Path $InstallDir $Name) -Force
}

function New-Shortcut($ShortcutPath, $TargetPath, $WorkingDirectory, $IconPath, $Description) {
    $parent = Split-Path -Parent $ShortcutPath
    if (!(Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = $IconPath
    $shortcut.Description = $Description
    $shortcut.Save()
}

function Install-CodeSigningCertificate($InstallDir) {
    $certificatePath = Join-Path $InstallDir "AgenticRevenueVision-CodeSigning.cer"
    if (!(Test-Path -LiteralPath $certificatePath)) {
        throw "Certificate file not found: $certificatePath"
    }

    Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
    Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher | Out-Null
}

function Write-Uninstaller($InstallDir) {
    $uninstallerPath = Join-Path $InstallDir "Uninstall-CodexProfileSwitcher.ps1"
    $script = @'
$ErrorActionPreference = "Stop"
$appName = "Codex Profile Switcher"
$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Codex Profile Switcher"
$desktopShortcutPath = Join-Path ([Environment]::GetFolderPath("DesktopDirectory")) "Codex Profile Switcher.lnk"
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexProfileSwitcher"

try {
    Remove-Item -LiteralPath $desktopShortcutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $startMenuDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue

    $self = $MyInvocation.MyCommand.Path
    $cleanup = @"
Start-Sleep -Milliseconds 500
Remove-Item -LiteralPath '$installDir' -Recurse -Force -ErrorAction SilentlyContinue
"@
    $cleanupPath = Join-Path $env:TEMP "codex-profile-switcher-uninstall.ps1"
    Set-Content -LiteralPath $cleanupPath -Value $cleanup -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$cleanupPath`"" -WindowStyle Hidden
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("$appName was uninstalled.", "$appName Uninstall", "OK", "Information") | Out-Null
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Uninstall failed: $($_.Exception.Message)", "$appName Uninstall", "OK", "Error") | Out-Null
}
'@

    Set-Content -LiteralPath $uninstallerPath -Value $script -Encoding UTF8
    return $uninstallerPath
}

function Register-UninstallEntry($InstallDir, $ExePath, $UninstallerPath) {
    if (!(Test-Path -LiteralPath $UninstallKey)) {
        New-Item -Path $UninstallKey -Force | Out-Null
    }

    New-ItemProperty -Path $UninstallKey -Name "DisplayName" -Value $AppName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name "DisplayVersion" -Value "2.0.0.0" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name "Publisher" -Value $CompanyName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name "InstallLocation" -Value $InstallDir -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name "DisplayIcon" -Value $ExePath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name "UninstallString" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$UninstallerPath`"" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name "NoModify" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name "NoRepair" -Value 1 -PropertyType DWord -Force | Out-Null
}

function Install-CodexProfileSwitcher($InstallDir, $CreateDesktopShortcut, $InstallCertificate) {
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        throw "Install folder cannot be empty."
    }

    if (!(Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir | Out-Null
    }

    Copy-PayloadFile "CodexProfileSwitcher.exe" $InstallDir
    Copy-PayloadFile "CodexProfileSwitcher.exe.config" $InstallDir
    Copy-PayloadFile "CodexProfileSwitcher.ico" $InstallDir
    Copy-PayloadFile "README.txt" $InstallDir
    Copy-PayloadFile "AgenticRevenueVision-CodeSigning.cer" $InstallDir
    Copy-PayloadFile "Install-AgenticRevenueVisionCertificate.ps1" $InstallDir

    $exePath = Join-Path $InstallDir "CodexProfileSwitcher.exe"
    $iconPath = Join-Path $InstallDir "CodexProfileSwitcher.ico"
    $uninstallerPath = Write-Uninstaller $InstallDir

    New-Shortcut (Join-Path $StartMenuDir "Codex Profile Switcher.lnk") $exePath $InstallDir $iconPath $AppName
    New-Shortcut (Join-Path $StartMenuDir "Uninstall Codex Profile Switcher.lnk") "powershell.exe" $InstallDir "powershell.exe" "Uninstall $AppName"
    $uninstallShortcut = Join-Path $StartMenuDir "Uninstall Codex Profile Switcher.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($uninstallShortcut)
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$uninstallerPath`""
    $shortcut.Save()

    if ($CreateDesktopShortcut) {
        New-Shortcut $DesktopShortcutPath $exePath $InstallDir $iconPath $AppName
    }

    if ($InstallCertificate) {
        Install-CodeSigningCertificate $InstallDir
    }

    Register-UninstallEntry $InstallDir $exePath $uninstallerPath
    Remove-Item -LiteralPath $PayloadDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Show-InstallerDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$AppName Setup"
    $form.ClientSize = New-Object System.Drawing.Size(520, 315)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Install $AppName"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(22, 20)
    $form.Controls.Add($title)

    $summary = New-Object System.Windows.Forms.Label
    $summary.Text = "This installs the app for the current Windows user, adds Start Menu shortcuts, and registers an uninstaller in Windows Apps & features."
    $summary.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $summary.Location = New-Object System.Drawing.Point(24, 58)
    $summary.Size = New-Object System.Drawing.Size(460, 42)
    $form.Controls.Add($summary)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = "Install folder"
    $pathLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $pathLabel.Location = New-Object System.Drawing.Point(24, 113)
    $pathLabel.AutoSize = $true
    $form.Controls.Add($pathLabel)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Text = $DefaultInstallDir
    $pathBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $pathBox.Location = New-Object System.Drawing.Point(27, 137)
    $pathBox.Size = New-Object System.Drawing.Size(360, 24)
    $form.Controls.Add($pathBox)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Text = "Browse"
    $browseButton.Location = New-Object System.Drawing.Point(400, 136)
    $browseButton.Size = New-Object System.Drawing.Size(85, 27)
    $form.Controls.Add($browseButton)

    $desktopBox = New-Object System.Windows.Forms.CheckBox
    $desktopBox.Text = "Create desktop shortcut"
    $desktopBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $desktopBox.Checked = $true
    $desktopBox.AutoSize = $true
    $desktopBox.Location = New-Object System.Drawing.Point(28, 182)
    $form.Controls.Add($desktopBox)

    $certBox = New-Object System.Windows.Forms.CheckBox
    $certBox.Text = "Trust the included Agentic Revenue Vision signing certificate for this Windows user"
    $certBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $certBox.Checked = $false
    $certBox.AutoSize = $true
    $certBox.Location = New-Object System.Drawing.Point(28, 210)
    $form.Controls.Add($certBox)

    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Text = "Install"
    $installButton.Location = New-Object System.Drawing.Point(315, 262)
    $installButton.Size = New-Object System.Drawing.Size(85, 32)
    $form.Controls.Add($installButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(410, 262)
    $cancelButton.Size = New-Object System.Drawing.Size(85, 32)
    $form.Controls.Add($cancelButton)

    $browseButton.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Choose install folder"
        $folderDialog.SelectedPath = $pathBox.Text
        if ($folderDialog.ShowDialog($form) -eq "OK") {
            $pathBox.Text = $folderDialog.SelectedPath
        }
    })

    $script:InstallSucceeded = $false
    $installButton.Add_Click({
        try {
            $installButton.Enabled = $false
            $cancelButton.Enabled = $false
            Install-CodexProfileSwitcher $pathBox.Text $desktopBox.Checked $certBox.Checked
            $script:InstallSucceeded = $true
            Show-InstallerInfo "$AppName was installed successfully."
            $form.Close()
        } catch {
            $installButton.Enabled = $true
            $cancelButton.Enabled = $true
            Show-InstallerError "Install failed: $($_.Exception.Message)"
        }
    })

    $cancelButton.Add_Click({ $form.Close() })
    [void]$form.ShowDialog()
    return $script:InstallSucceeded
}

try {
    if ($Unattended) {
        Install-CodexProfileSwitcher $DefaultInstallDir $true $false
    } else {
        [void](Show-InstallerDialog)
    }
} catch {
    Show-InstallerError "Install failed: $($_.Exception.Message)"
    exit 1
}

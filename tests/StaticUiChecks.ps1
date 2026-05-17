$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "..\CodexProfileSwitcher.ps1"
$readmePath = Join-Path $PSScriptRoot "..\README.txt"
$installerPath = Join-Path $PSScriptRoot "..\installer\CodexProfileSwitcherInstaller.ps1"
$buildInstallerPath = Join-Path $PSScriptRoot "..\Build-Installer.ps1"

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $scriptPath), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) {
    $details = ($errors | ForEach-Object { "$($_.Message) at line $($_.Extent.StartLineNumber)" }) -join "`n"
    throw "CodexProfileSwitcher.ps1 has parser errors:`n$details"
}

$installerTokens = $null
$installerErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $installerPath), [ref]$installerTokens, [ref]$installerErrors) | Out-Null
if ($installerErrors) {
    $details = ($installerErrors | ForEach-Object { "$($_.Message) at line $($_.Extent.StartLineNumber)" }) -join "`n"
    throw "CodexProfileSwitcherInstaller.ps1 has parser errors:`n$details"
}

$buildInstallerTokens = $null
$buildInstallerErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $buildInstallerPath), [ref]$buildInstallerTokens, [ref]$buildInstallerErrors) | Out-Null
if ($buildInstallerErrors) {
    $details = ($buildInstallerErrors | ForEach-Object { "$($_.Message) at line $($_.Extent.StartLineNumber)" }) -join "`n"
    throw "Build-Installer.ps1 has parser errors:`n$details"
}

$content = Get-Content -LiteralPath $scriptPath -Raw
$readmeContent = Get-Content -LiteralPath $readmePath -Raw
$installerContent = Get-Content -LiteralPath $installerPath -Raw
$buildInstallerContent = Get-Content -LiteralPath $buildInstallerPath -Raw

function Assert-Contains($Pattern, $Message) {
    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-ReadmeContains($Pattern, $Message) {
    if ($readmeContent -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-InstallerContains($Pattern, $Message) {
    if ($installerContent -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-BuildInstallerContains($Pattern, $Message) {
    if ($buildInstallerContent -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains($Pattern, $Message) {
    if ($content -match $Pattern) {
        throw $Message
    }
}

Assert-Contains '\$HeaderText = "\$AppName by A\.R\.V"' "Header should keep the A.R.V title treatment."
Assert-Contains '\$form\.ClientSize = New-Object System\.Drawing\.Size\(600, 560\)' "Main form should leave room for profile emails and usage limits."
Assert-Contains '\$ColorBlue = \[System\.Drawing\.Color\]::FromArgb\(11, 102, 216\)' "Main UI should use the Stitch brand blue."
Assert-Contains '\$modeLight\.Text = "Light"' "Main UI should show the light mode segment."
Assert-Contains '\$modeDark\.Text = "Dark"' "Main UI should show the dark mode segment."
Assert-Contains 'function Set-ThemeColors' "Theme toggle should centralize light and dark color tokens."
Assert-Contains 'function Apply-Theme' "Theme toggle should repaint the app from shared color tokens."
Assert-Contains '\$script:IsDarkMode = \$false' "Theme toggle should track the current mode."
Assert-Contains 'if \(\$DarkMode\)' "Dark mode should define a dark color palette."
Assert-Contains '\$modeLight\.Add_Click\(\{ Apply-Theme \$false \}\)' "Light segment should switch back to light mode."
Assert-Contains '\$modeDark\.Add_Click\(\{ Apply-Theme \$true \}\)' "Dark segment should switch to dark mode."
Assert-Contains 'Update-BorderPaintStyle \$usagePanel 8 \$ColorBorder \$ColorPanel' "Dark mode should update usage panel rounded-section colors."
Assert-Contains '\$list\.Invalidate\(\)' "Theme changes should repaint the owner-drawn profile list."
Assert-Contains '\$hideEmailsToggle\.Text = "Hide emails"' "Main UI should provide a universal email privacy toggle."
Assert-Contains '\$hideEmailsToggle\.Location = New-Object System\.Drawing\.Point\(38, 415\)' "Hide emails should sit below the profile selector."
Assert-Contains 'function Get-ProfileEmail' "Main UI should read profile email metadata locally."
Assert-Contains 'ConvertFrom-Base64Url' "Profile email extraction should decode only JWT payload metadata."
Assert-Contains 'function Get-MaskedEmail' "Profile emails should be masked per character before the domain."
Assert-Contains 'function Get-LatestCodexUsage' "Usage panel should read real local Codex usage snapshots."
Assert-Contains 'function Save-UsageSnapshotToProfile' "Active usage should be saved into the active profile folder."
Assert-Contains 'function Get-ProfileAuthTokens' "Usage refresh should read auth tokens only inside a narrow profile helper."
Assert-Contains 'function Invoke-ChatGptUsageRequest' "Usage refresh should call the ChatGPT usage endpoint per saved profile."
Assert-Contains 'function Invoke-ChatGptTokenRefresh' "Usage refresh should refresh expired OAuth tokens safely."
Assert-Contains 'function Update-ProfileAuthTokens' "Refreshed tokens should be saved back only to the matching profile folder."
Assert-Contains 'function Refresh-AllProfileUsageSnapshots' "Refresh should be able to update saved usage snapshots for every saved profile."
Assert-Contains 'backend-api/wham/usage' "Usage refresh should use the ChatGPT usage endpoint used by Codex."
Assert-Contains 'chatgpt-account-id' "Usage refresh should preserve the selected ChatGPT account id header."
Assert-Contains 'Get-LiveProfileUsage \$ProfileName' "Selected profile usage should try live per-profile data before local snapshots."
Assert-Contains 'Read-UsageSnapshotFile \(Get-UsageSnapshotPath \$ProfileName\)' "Selected profile usage should fall back to the saved local snapshot."
Assert-Contains 'function Update-UsagePanelForSelectedProfile' "Usage panel should update from the selected profile."
Assert-Contains 'rate_limits' "Usage panel should scan local session rate limit data."
Assert-Contains '\$statusPanel = New-Object System\.Windows\.Forms\.Panel' "Main UI should use the compact Stitch status strip."
Assert-Contains 'function Set-OperationStatus' "Background operations should update the new status strip instead of a removed status label."
Assert-NotContains '\$status\.Text' "Background operations should not write to the removed status label."
Assert-Contains '\$dialog\.Size = New-Object System\.Drawing\.Size\(560, 395\)' "Setup consent should leave room for the authorized-use agreement."
Assert-Contains 'Use this app only with accounts you own, purchased, or are otherwise authorized to use' "Setup consent should explain authorized account use."
Assert-Contains 'Do not use this app to share accounts, bypass account restrictions, or violate OpenAI' "Setup consent should prohibit account-sharing and terms violations."
Assert-Contains 'Agentic Revenue Vision provides this utility for lawful personal account switching only and is not responsible for misuse by users' "Setup consent should disclaim responsibility for user misuse."
Assert-Contains '\$termsBox\.Text = "I agree to use this app only with accounts I am authorized to use\."' "Setup consent should require explicit authorized-use agreement."
Assert-Contains '\$btnContinue\.Enabled = \(\$consentBox\.Checked -and \$termsBox\.Checked\)' "Setup consent should require both safety and terms checkboxes."
Assert-Contains '\$profilesLabel\.Text = "Profiles"' "Main view should label the profile column."
Assert-Contains '\$actionsLabel\.Text = "Actions"' "Main view should label the action column."
Assert-Contains '\$list\.DrawMode = \[System\.Windows\.Forms\.DrawMode\]::OwnerDrawFixed' "Profile list should render multi-line status rows."
Assert-Contains '\$list\.ItemHeight = 74' "Profile rows should include profile name, email, and status."
Assert-Contains '\$profilePanel\.Location = New-Object System\.Drawing\.Point\(24, 160\)' "Profile panel should sit below the Profiles heading."
Assert-Contains '\$list\.BackColor = \$ColorPanel' "Profile list should use the white panel surface token."
Assert-Contains '"Active profile"' "Profile rows should show the active profile status."
Assert-Contains '"Saved login"' "Profile rows should show saved login status."
Assert-Contains '"No saved login"' "Profile rows should show missing login status."
Assert-Contains 'elseif \(\$script:HideProfileEmails\) \{ Get-MaskedEmail \$email \}' "Profile emails should be maskable before the domain."

Assert-Contains '\$btnNewLogin\.Text = "Add account"' "Add-account action should use the compact label."
Assert-Contains '\$btnSave\.Text = "Save active login"' "Save action should use the compact label."
Assert-Contains '\$btnSwitch\.Text = "Switch profile"' "Switch action should use the compact label."
Assert-Contains '\$btnRename\.Text = "Rename"' "Rename action should use the compact label."
Assert-Contains '\$btnDelete\.Text = "Delete"' "Delete action should use the compact label."
Assert-Contains '\$btnRefresh\.Text = "Refresh"' "Refresh action should remain in the action stack."
Assert-Contains '\$btnSwitch\.Location = New-Object System\.Drawing\.Point\(378, 160\)' "Switch profile should be the top primary action."
Assert-Contains 'Set-ActionButtonStyle \$btnSwitch "primary"' "Switch profile should use the blue primary button style."
Assert-Contains 'Set-ActionButtonStyle \$btnDelete "danger"' "Delete should use the restrained danger outline style."
Assert-Contains '\$btnRename\.Location = New-Object System\.Drawing\.Point\(378, 312\)' "Rename should be in the left half of the paired action row."
Assert-Contains '\$btnDelete\.Location = New-Object System\.Drawing\.Point\(482, 312\)' "Delete should be in the right half of the paired action row."
Assert-Contains '\$Button\.Add_MouseEnter' "Action buttons should customize hover styling."
Assert-Contains '\$ColorDanger = \[System\.Drawing\.Color\]::FromArgb\(180, 35, 24\)' "Danger actions should use the Stitch red."
Assert-Contains 'function New-RoundedRectanglePath' "Custom-styled Delete button should paint rounded corners."
Assert-Contains 'function Set-ActionButtonStyle' "Action buttons should custom-paint the Stitch rounded button style."
Assert-Contains '\$btnRefresh\.Location = New-Object System\.Drawing\.Point\(378, 360\)' "Refresh should sit below the rename/delete row."
Assert-Contains '\$usagePanel = New-Object System\.Windows\.Forms\.Panel' "Main UI should include the usage limits panel."
Assert-Contains '\$usagePanel\.BackColor = \$ColorPanel' "Usage panel should match the light UI."
Assert-Contains 'Add-BorderPaint \$usagePanel 8 \$ColorBorder \$ColorPanel' "Usage panel should use the same rounded section styling."
Assert-Contains '\$tutorialLink = New-Object System\.Windows\.Forms\.LinkLabel' "Main UI should include a clickable tutorial link."
Assert-Contains '\$tutorialLink\.Text = "Watch tutorial"' "Tutorial link should use compact link text."
Assert-Contains '\$tutorialLink\.Location = New-Object System\.Drawing\.Point\(378, 536\)' "Tutorial link should sit below the usage section on the bottom right."
Assert-Contains 'Start-Process "https://youtu\.be/JA8C-SHFS50"' "Tutorial link should open the requested video URL."
Assert-Contains '"5h Limit \(5h\)"' "Usage panel should show the 5h limit row."
Assert-Contains '"Weekly Limit \(7d\)"' "Usage panel should show the weekly limit row."
Assert-Contains '"Credits: 0"' "Usage panel should show credits."
Assert-Contains '"Last updated: Never"' "Usage panel should show the fallback update timestamp."
Assert-Contains '\$limit5hValue\.Text = \$primary\.ResetText' "Usage panel should display real 5h usage when available."
Assert-Contains '\$weeklyValue\.Text = \$secondary\.ResetText' "Usage panel should display real weekly usage when available."
Assert-Contains '\$list\.Add_SelectedIndexChanged\(\{' "Profile selection should drive dependent UI updates."
Assert-Contains 'Update-UsagePanelForSelectedProfile' "Profile selection should refresh the usage panel."
Assert-Contains '\$btnRefresh\.Add_Click\(\{ Refresh-AllProfileUsageSnapshots; Refresh-UI \}\)' "Refresh should update live usage snapshots before repainting the UI."

Assert-Contains '\[void\]\(Save-CurrentToProfile \$active\)' "Internal save counts should not leak into GUI output."
Assert-Contains '\[void\]\(Restore-ProfileToCurrent \$target\)' "Internal restore counts should not leak into GUI output."

Assert-ReadmeContains 'Codex Profile Switcher for Windows' "README should describe the app."
Assert-ReadmeContains 'Does not show, export, upload, or inspect raw credentials/tokens' "README should retain the credential-safety note."
Assert-ReadmeContains 'Decodes only the local ID token payload to show non-secret account metadata' "README should document the email metadata behavior."
Assert-ReadmeContains 'Usage refresh reads saved profile auth locally, sends tokens only as HTTPS authorization headers' "README should document live usage safety boundaries."
Assert-ReadmeContains 'Use the Light/Dark segmented control to switch the whole interface theme' "README should document the working theme toggle."
Assert-ReadmeContains 'authorized-use agreement' "README should document the first-time authorized-use agreement."
Assert-ReadmeContains 'Users are responsible for how they use the app' "README should document user responsibility for misuse."
Assert-ReadmeContains 'Watch tutorial' "README should document the tutorial link."
Assert-ReadmeContains 'https://youtu\.be/JA8C-SHFS50' "README should document the tutorial URL."
Assert-ReadmeContains 'CodexProfileSwitcherSetup\.exe installs the app for the current Windows user' "README should document the installer."

Assert-InstallerContains 'Programs\\Codex Profile Switcher' "Installer should install under the current user's local Programs folder."
Assert-InstallerContains 'Microsoft\\Windows\\Start Menu\\Programs\\Codex Profile Switcher' "Installer should create Start Menu shortcuts."
Assert-InstallerContains 'Cert:\\CurrentUser\\Root' "Installer should optionally trust the public certificate for the current user."
Assert-InstallerContains 'CurrentVersion\\Uninstall\\CodexProfileSwitcher' "Installer should register a current-user uninstall entry."
Assert-InstallerContains 'CodexProfileSwitcherPayload' "Installer should use the embedded payload extraction folder."
Assert-BuildInstallerContains 'CodexProfileSwitcherSetup\.exe' "Build script should produce the setup executable."
Assert-BuildInstallerContains '-embedFiles \$embedFiles' "Build script should embed app payload files."
Assert-BuildInstallerContains '-iconFile \$iconFile' "Build script should embed the app icon in the installer."

"Static UI checks passed."

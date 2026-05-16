$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "..\CodexProfileSwitcher.ps1"
$readmePath = Join-Path $PSScriptRoot "..\README.txt"

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $scriptPath), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) {
    $details = ($errors | ForEach-Object { "$($_.Message) at line $($_.Extent.StartLineNumber)" }) -join "`n"
    throw "CodexProfileSwitcher.ps1 has parser errors:`n$details"
}

$content = Get-Content -LiteralPath $scriptPath -Raw
$readmeContent = Get-Content -LiteralPath $readmePath -Raw

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

Assert-Contains '\$HeaderText = "\$AppName by A\.R\.V"' "Header should keep the A.R.V title treatment."
Assert-Contains '\$form\.Size = New-Object System\.Drawing\.Size\(560, 405\)' "Main form should keep the compact native layout."
Assert-Contains '\$list\.DrawMode = \[System\.Windows\.Forms\.DrawMode\]::OwnerDrawFixed' "Profile list should render multi-line status rows."
Assert-Contains '\$list\.ItemHeight = 48' "Profile rows should be tall enough for profile name and status."
Assert-Contains '"Active profile"' "Profile rows should show the active profile status."
Assert-Contains '"Saved login"' "Profile rows should show saved login status."
Assert-Contains '"No saved login"' "Profile rows should show missing login status."

Assert-Contains '\$btnNewLogin\.Text = "Add account"' "Add-account action should use the compact label."
Assert-Contains '\$btnSave\.Text = "Save active login"' "Save action should use the compact label."
Assert-Contains '\$btnSwitch\.Text = "Switch profile"' "Switch action should use the compact label."
Assert-Contains '\$btnRename\.Text = "Rename"' "Rename action should use the compact label."
Assert-Contains '\$btnDelete\.Text = "Delete"' "Delete action should use the compact label."
Assert-Contains '\$btnRefresh\.Text = "Refresh"' "Refresh action should remain in the action stack."
Assert-Contains '\$btnRename\.Location = New-Object System\.Drawing\.Point\(300, 237\)' "Rename should be in the left half of the paired action row."
Assert-Contains '\$btnDelete\.Location = New-Object System\.Drawing\.Point\(410, 237\)' "Delete should be in the right half of the paired action row."
Assert-Contains '\$btnDelete\.Add_MouseEnter' "Delete should customize hover styling."
Assert-Contains 'FromArgb\(210, 45, 55\)' "Delete hover border should use a red color."
Assert-Contains 'function New-RoundedRectanglePath' "Custom-styled Delete button should paint rounded corners."
Assert-Contains '\$btnDelete\.Add_Paint' "Delete button should custom-paint its rounded hover border."
Assert-Contains '\$btnRefresh\.Location = New-Object System\.Drawing\.Point\(300, 279\)' "Refresh should sit below the rename/delete row."

Assert-Contains '\[void\]\(Save-CurrentToProfile \$active\)' "Internal save counts should not leak into GUI output."
Assert-Contains '\[void\]\(Restore-ProfileToCurrent \$target\)' "Internal restore counts should not leak into GUI output."

Assert-ReadmeContains 'Codex Profile Switcher for Windows' "README should describe the app."
Assert-ReadmeContains 'Does not show, decode, export, upload, or inspect credentials/tokens' "README should retain the credential-safety note."

"Static UI checks passed."

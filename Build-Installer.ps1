$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$installerScript = Join-Path $root "installer\CodexProfileSwitcherInstaller.ps1"
$outputFile = Join-Path $root "CodexProfileSwitcherSetup.exe"
$iconFile = Join-Path $root "CodexProfileSwitcher.ico"

$requiredFiles = @(
    "CodexProfileSwitcher.exe",
    "CodexProfileSwitcher.exe.config",
    "CodexProfileSwitcher.ico",
    "README.txt",
    "AgenticRevenueVision-CodeSigning.cer",
    "Install-AgenticRevenueVisionCertificate.ps1"
)

foreach ($file in $requiredFiles) {
    $path = Join-Path $root $file
    if (!(Test-Path -LiteralPath $path)) {
        throw "Required installer payload file is missing: $file"
    }
}

if (!(Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    throw "Invoke-ps2exe is not available. Install the ps2exe PowerShell module before building the installer."
}

$embedFiles = @{}
foreach ($file in $requiredFiles) {
    $embedFiles["%TEMP%\CodexProfileSwitcherPayload\$file"] = Join-Path $root $file
}

Invoke-ps2exe `
    -inputFile $installerScript `
    -outputFile $outputFile `
    -embedFiles $embedFiles `
    -iconFile $iconFile `
    -noConsole `
    -STA `
    -winFormsDPIAware `
    -title "Codex Profile Switcher Setup" `
    -description "Installer for Codex Profile Switcher" `
    -company "Agentic Revenue Vision" `
    -product "Codex Profile Switcher" `
    -copyright "Agentic Revenue Vision" `
    -version "2.0.0.0"

$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Thumbprint -eq "577659AD90EA03BB8D9ED4E7F0BDB3CD0DFCC3DE" } |
    Select-Object -First 1

if ($null -ne $cert) {
    Set-AuthenticodeSignature -FilePath $outputFile -Certificate $cert | Out-Null
    Write-Host "Signed installer with Agentic Revenue Vision code-signing certificate."
} else {
    Write-Warning "Code-signing certificate was not found. Installer was built but not signed."
}

Write-Host "Built installer: $outputFile"

$ErrorActionPreference = "Stop"

$certificatePath = Join-Path $PSScriptRoot "AgenticRevenueVision-CodeSigning.cer"
if (!(Test-Path $certificatePath)) {
    throw "Certificate file not found: $certificatePath"
}

$rootResult = Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:\CurrentUser\Root
$publisherResult = Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher

Write-Host "Installed certificate for current user."
Write-Host "Root store thumbprint: $($rootResult.Thumbprint)"
Write-Host "Trusted Publisher thumbprint: $($publisherResult.Thumbprint)"

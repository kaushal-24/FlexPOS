[CmdletBinding()]
param(
  [switch]$SkipBuilds,
  [switch]$SkipLiveIntegration,
  [string]$ConfigPath = 'config/prod.json',
  [string]$IntegrationDevice = 'windows'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Invoke-GateCommand {
  param(
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  Write-Host "`n> $File $($Arguments -join ' ')" -ForegroundColor Cyan
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Release gate failed with exit code ${LASTEXITCODE}: $File $($Arguments -join ' ')"
  }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw "Missing production configuration '$ConfigPath'. Copy config/prod.example.json and fill only the publishable key."
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($config.SUPABASE_URL -notmatch '^https://[a-z0-9-]+\.supabase\.co$') {
  throw "Production configuration must point to a Supabase HTTPS project URL."
}
if ([string]::IsNullOrWhiteSpace([string]$config.SUPABASE_PUBLISHABLE_KEY) -or
    $config.SUPABASE_PUBLISHABLE_KEY -match 'replace_with|your_key') {
  throw "Production configuration still contains a placeholder publishable key."
}

Invoke-GateCommand 'flutter' @('pub', 'get')
Invoke-GateCommand 'flutter' @('gen-l10n')
Invoke-GateCommand 'dart' @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test', 'tool')
Invoke-GateCommand 'flutter' @('analyze', '--no-pub')
Invoke-GateCommand 'flutter' @('test', '--no-pub')
Invoke-GateCommand 'dart' @('run', 'tool/performance_profile.dart')

if (-not $SkipLiveIntegration) {
  $liveDefineNames = @(
    'SUPABASE_URL',
    'SUPABASE_PUBLISHABLE_KEY',
    'FLEXPOS_TEST_EMAIL',
    'FLEXPOS_TEST_PASSWORD',
    'FLEXPOS_TEST_BUSINESS_ID'
  )
  $missingLiveDefines = @(
    $liveDefineNames | Where-Object {
      [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
    }
  )
  if ($missingLiveDefines.Count -eq 0) {
    $integrationArguments = @(
      'test',
      'integration_test/production_smoke_test.dart',
      '-d',
      $IntegrationDevice
    )
    foreach ($name in $liveDefineNames + @(
        'FLEXPOS_TEST_SALE_ID',
        'FLEXPOS_TEST_SECOND_EMAIL',
        'FLEXPOS_TEST_SECOND_PASSWORD',
        'FLEXPOS_TEST_SECOND_BUSINESS_ID'
      )) {
      $value = [Environment]::GetEnvironmentVariable($name)
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        $integrationArguments += "--dart-define=$name=$value"
      }
    }
    Invoke-GateCommand 'flutter' $integrationArguments
  } else {
    Write-Host "`nLive integration smoke tests require operator-supplied FLEXPOS_* defines." -ForegroundColor Yellow
    Write-Host 'Run docs/TESTING_AND_PRODUCTION_VERIFICATION.md with disposable FlexPOS-2 fixtures before release.' -ForegroundColor Yellow
  }
}

if (-not $SkipBuilds) {
  Invoke-GateCommand 'flutter' @('build', 'web', '--release', "--dart-define-from-file=$ConfigPath")
  Invoke-GateCommand 'flutter' @('build', 'apk', '--release', "--dart-define-from-file=$ConfigPath")
  Invoke-GateCommand 'flutter' @('build', 'appbundle', '--release', "--dart-define-from-file=$ConfigPath")
  Invoke-GateCommand 'flutter' @('build', 'windows', '--release', "--dart-define-from-file=$ConfigPath")
}

$keyProperties = Join-Path $projectRoot 'android/key.properties'
if (-not (Test-Path -LiteralPath $keyProperties)) {
  Write-Warning 'android/key.properties is missing. Android release outputs use the debug key and must not be distributed.'
} else {
  Write-Host 'Android upload-key configuration detected. Verify the APK/AAB certificate with apksigner before distribution.' -ForegroundColor Green
}

Write-Host "`nAutomated release gates completed. Physical scanner evidence, Apple signing, store credentials, and production payment credentials remain operator-owned gates." -ForegroundColor Green

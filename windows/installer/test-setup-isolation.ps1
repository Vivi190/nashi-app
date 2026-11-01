# Test the PR #29 installer using synthetic files and an isolated directory.
# Does not launch Nashi or touch %LOCALAPPDATA%\Nashi.
param(
    [string]$MakeNsis = 'makensis'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$root = Join-Path $env:TEMP ('nashi-setup-test-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $root 'payload'
$target = Join-Path $root 'installed'
$setup = Join-Path $root 'Nashi-Setup-test.exe'
$reg = 'HKCU:\Software\Nashi'
$unreg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Nashi'
$stage = Join-Path $root '.nashi-setup-staging'
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Nashi.lnk'
if ((Test-Path $reg) -or (Test-Path $unreg) -or (Test-Path $startMenu)) {
    throw 'Nashi Setup registration already exists; refusing isolated test to protect the installed application.'
}
New-Item -ItemType Directory -Path $payload -Force | Out-Null
# A pre-existing sibling folder must never be deleted by the installer.
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Set-Content -LiteralPath (Join-Path $stage 'unrelated-user-file.txt') -Value 'must survive' -NoNewline
Set-Content -LiteralPath (Join-Path $payload 'Nashi.exe') -Value 'synthetic test only' -NoNewline
Set-Content -LiteralPath (Join-Path $payload 'Nashi.dll') -Value 'synthetic dll' -NoNewline
$installed = $false
try {
    Push-Location $repo
    try {
        & $MakeNsis /NOCD /DNASHI_VERSION=0.7.10 "/DNASHI_PAYLOAD=$payload" "/DNASHI_OUT=$setup" 'windows/installer/windows-setup.nsi' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "NSIS failed with $LASTEXITCODE" }
    } finally { Pop-Location }
    $exe = Start-Process -FilePath $setup -ArgumentList @('/S', '/nolaunch', "/D=$target") -PassThru -Wait
    if ($exe.ExitCode -ne 0) { throw "Installer failed: $($exe.ExitCode)" }
    $installed = $true
    if (-not (Test-Path (Join-Path $target 'Nashi.exe'))) { throw 'Installed executable missing' }
    if (-not (Test-Path (Join-Path $target 'uninst.exe'))) { throw 'Uninstaller missing' }
    if ((Get-ItemProperty $reg).InstallPath -ne $target) { throw 'Install registration points elsewhere' }
    if (-not (Test-Path (Join-Path $stage 'unrelated-user-file.txt'))) { throw 'FAILED: installer deleted a pre-existing sibling folder' }
    $unexpected = @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.FullName -notin @($payload, $target, $stage) })
    if ($unexpected.Count -ne 0) { throw ('FAILED: installer left temporary directory: ' + ($unexpected.FullName -join ', ')) }
    Write-Output 'PASS: existing sibling folder preserved; staging directory removed'
    $again = Start-Process -FilePath $setup -ArgumentList @('/S', '/nolaunch', "/D=$target") -PassThru -Wait
    if ($again.ExitCode -ne 0) { throw "Reinstall failed: $($again.ExitCode)" }
    if (-not (Test-Path (Join-Path $target 'Nashi.exe'))) { throw 'Reinstalled executable missing' }
    if (-not (Test-Path (Join-Path $stage 'unrelated-user-file.txt'))) { throw 'Reinstall deleted the unrelated folder' }
    $unexpected = @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.FullName -notin @($payload, $target, $stage) })
    if ($unexpected.Count -ne 0) { throw ('Reinstall left temporary directory: ' + ($unexpected.FullName -join ', ')) }
    Write-Output 'PASS: reinstall preserved unrelated folder without staging debris'
} finally {
    if ($installed -and (Test-Path (Join-Path $target 'uninst.exe'))) {
        $uninstaller = Start-Process -FilePath (Join-Path $target 'uninst.exe') -ArgumentList '/S' -PassThru -Wait
        if ($uninstaller.ExitCode -ne 0) { Write-Warning "Uninstaller failed: $($uninstaller.ExitCode)" }
        if ((Test-Path $target) -or (Test-Path $reg) -or (Test-Path $unreg)) {
            throw 'Uninstall did not remove the test application and its registry entries'
        }
        if (-not (Test-Path (Join-Path $stage 'unrelated-user-file.txt'))) {
            throw 'Uninstall deleted a sibling user folder'
        }
        Write-Output 'PASS: uninstall removed application/registry and preserved unrelated files'
    }
    if ((Test-Path $reg) -and ((Get-ItemProperty $reg).InstallPath -eq $target)) {
        Remove-Item -Path $reg -Recurse -Force
        if (Test-Path $unreg) { Remove-Item -Path $unreg -Recurse -Force }
    }
    if (Test-Path $startMenu) { Remove-Item -LiteralPath $startMenu -Force }
    # On failure the unique temp fixture remains available for diagnosis.
}
# Only clean up once all assertions and the uninstall proof have passed.
Remove-Item -LiteralPath $root -Recurse -Force

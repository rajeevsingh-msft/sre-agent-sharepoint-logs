#requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipWindowsPowerShellCompatibility)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('lab-transfer-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
$script:passed = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Expected)
    $failure = $null
    try { $null = & $Action } catch { $failure = $_ }
    Assert-True ($null -ne $failure -and $failure.Exception.Message -like "*$Expected*") "Expected '$Expected'; received '$failure'."
    $script:passed++
}
function Invoke-Guest {
    param([string]$Payload, [string]$Folder)
    $isolated = $Payload.Replace('C:\Temp\SP-LabSetup', $Folder.Replace("'", "''"))
    & ([scriptblock]::Create($isolated)) | ConvertFrom-Json
}
try {
    $output = Join-Path $temporary 'transfer.ps1'
    $null = & "$root\scripts\New-LabSetupTransfer.ps1" -OutputPath $output -WhatIf
    Assert-True (-not (Test-Path -LiteralPath $output)) 'WhatIf wrote a payload.'
    $script:passed++
    $info = & "$root\scripts\New-LabSetupTransfer.ps1" -OutputPath $output
    $payload = [IO.File]::ReadAllText($output)
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($payload, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Generated guest payload did not parse.'
    Assert-True ($info.files.Count -eq 2) 'Expected exactly two packaged setup files.'
    $script:passed++
    $guestFolder = Join-Path $temporary 'vm\stage'
    $result = Invoke-Guest $payload $guestFolder
    Assert-True ($result.kind -eq 'uls-lab-files-staged' -and $result.files.Count -eq 2) 'Guest result contract differs.'
    foreach ($file in $result.files) {
        $source = Join-Path "$root\scripts" $file.name
        $destination = Join-Path $guestFolder $file.name
        Assert-True ($file.status -eq 'created') 'New file was not reported created.'
        Assert-True ($file.sha256 -eq (Get-FileHash -LiteralPath $source).Hash) 'Source hash differs.'
        Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($source)) -ceq
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($destination))) 'Transferred bytes changed.'
    }
    Assert-True (@(Get-ChildItem -LiteralPath $guestFolder -File).Count -eq 2) 'Unexpected files were staged.'
    $script:passed++
    $repeat = Invoke-Guest $payload $guestFolder
    Assert-True (@($repeat.files | Where-Object status -NE 'kept').Count -eq 0) 'Identical files were rewritten.'
    $script:passed++
    $initializer = Join-Path $guestFolder 'Initialize-UlsLab.ps1'
    $reader = Join-Path $guestFolder 'Read-UlsLab.ps1'
    Remove-Item -LiteralPath $initializer
    [IO.File]::WriteAllText($reader, 'operator-owned different content')
    Assert-Throws { Invoke-Guest $payload $guestFolder } 'Existing file differs'
    Assert-True (-not (Test-Path -LiteralPath $initializer)) 'Preflight failure partially wrote setup files.'
    Assert-True ([IO.File]::ReadAllText($reader) -eq 'operator-owned different content') 'Different file was overwritten.'
    $hash = (Get-FileHash -LiteralPath $output).Hash
    Assert-Throws { & "$root\scripts\New-LabSetupTransfer.ps1" -OutputPath $output } 'already exists'
    Assert-True ((Get-FileHash -LiteralPath $output).Hash -eq $hash) 'Existing output changed.'
    Assert-Throws { & "$root\scripts\New-LabSetupTransfer.ps1" -OutputPath (Join-Path $temporary 'bad.txt') } 'new .ps1 file'
    Assert-Throws { & "$root\scripts\New-LabSetupTransfer.ps1" -OutputPath (Join-Path $temporary 'missing\out.ps1') } 'parent directory'
    $badFolder = Join-Path $temporary 'vm\not-a-directory'
    [IO.File]::WriteAllText($badFolder, 'keep')
    Assert-Throws { Invoke-Guest $payload $badFolder } 'normal staging directory'
    $directoryCase = Join-Path $temporary 'vm\directory-case'
    $null = New-Item -ItemType Directory -Path (Join-Path $directoryCase 'Read-UlsLab.ps1') -Force
    Assert-Throws { Invoke-Guest $payload $directoryCase } 'normal staging file'
    $badHash = $payload.Replace($info.files[0].sha256, ('0' * 64))
    Assert-Throws { Invoke-Guest $badHash (Join-Path $temporary 'vm\bad-hash') } 'Payload integrity check failed'
    $unexpected = $payload.Replace('"name":"Read-UlsLab.ps1"', '"name":"..\\unexpected.ps1"')
    Assert-Throws { Invoke-Guest $unexpected (Join-Path $temporary 'vm\bad-name') } 'Unexpected setup filename'
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $null = $encoding.GetString([IO.File]::ReadAllBytes($output))
    if ($SkipWindowsPowerShellCompatibility) {
        Write-Warning 'Windows PowerShell 5.1 execution explicitly skipped; guest compatibility remains unverified.'
    }
    else {
        $compatibilityFolder = Join-Path $temporary 'vm\windows-powershell'
        $compatibilityPath = Join-Path $temporary 'guest-compatibility.ps1'
        [IO.File]::WriteAllText($compatibilityPath, $payload.Replace('C:\Temp\SP-LabSetup', $compatibilityFolder))
        $json = & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -File $compatibilityPath
        Assert-True ($LASTEXITCODE -eq 0) 'Windows PowerShell 5.1 guest staging failed.'
        $compatibility = $json -join "`n" | ConvertFrom-Json
        Assert-True ($compatibility.kind -eq 'uls-lab-files-staged' -and $compatibility.files.Count -eq 2) 'Windows PowerShell result differs.'
        foreach ($file in $info.files) {
            Assert-True ((Get-FileHash -LiteralPath (Join-Path $compatibilityFolder $file.name)).Hash -eq $file.sha256) 'Windows PowerShell changed file bytes.'
        }
        $script:passed++
    }
    Write-Host "PASS: $script:passed local transfer checks; guest payload ran only in an isolated temporary folder. No Azure operations or initializer execution."
}
finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

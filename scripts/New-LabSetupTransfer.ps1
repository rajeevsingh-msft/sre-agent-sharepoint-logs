#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([IO.Path]::GetExtension($output) -ne '.ps1') { throw 'OutputPath must name a new .ps1 file.' }
if (Test-Path -LiteralPath $output) { throw 'OutputPath already exists; choose a new file rather than overwriting it.' }
if (-not (Test-Path -LiteralPath (Split-Path $output -Parent) -PathType Container)) {
    throw 'OutputPath parent directory must already exist.'
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $files = @(foreach ($name in @('Initialize-UlsLab.ps1', 'Read-UlsLab.ps1')) {
        $source = Get-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Force
        if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Expected a normal package file: $name"
        }
        $bytes = [IO.File]::ReadAllBytes($source.FullName)
        if ($bytes.Length -eq 0 -or $bytes.Length -gt 32KB) { throw "Invalid setup file size: $name" }
        [pscustomobject]@{
            name = $name
            sha256 = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
            base64 = [Convert]::ToBase64String($bytes)
        }
    })
}
finally { $sha.Dispose() }
$manifest = ConvertTo-Json -InputObject $files -Depth 3 -Compress
$template = @'
& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $folder = 'C:\Temp\SP-LabSetup'
    $files = ConvertFrom-Json '__LAB_FILES__'
    foreach ($directory in @((Split-Path $folder -Parent), $folder)) {
        if (Test-Path -LiteralPath $directory) {
            $item = Get-Item -LiteralPath $directory -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Expected a normal staging directory: $directory"
            }
        }
        else { $null = New-Item -ItemType Directory -Path $directory }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($file in $files) {
            if ($file.name -notin @('Initialize-UlsLab.ps1', 'Read-UlsLab.ps1')) {
                throw 'Unexpected setup filename.'
            }
            $bytes = [Convert]::FromBase64String($file.base64)
            $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
            if ($bytes.Length -eq 0 -or $bytes.Length -gt 32KB -or $hash -ne $file.sha256) {
                throw "Payload integrity check failed: $($file.name)"
            }
            $path = Join-Path $folder $file.name
            if (Test-Path -LiteralPath $path) {
                $item = Get-Item -LiteralPath $path -Force
                if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Expected a normal staging file: $path"
                }
                if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) {
                    throw "Existing file differs; not overwriting: $path"
                }
            }
        }
        $results = @(foreach ($file in $files) {
            $path = Join-Path $folder $file.name
            $status = 'kept'
            if (-not (Test-Path -LiteralPath $path)) {
                $bytes = [Convert]::FromBase64String($file.base64)
                $handle = [IO.File]::Open($path, 'CreateNew', 'Write', 'None')
                try { $handle.Write($bytes, 0, $bytes.Length) }
                finally { $handle.Dispose() }
                $status = 'created'
            }
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if ($hash -ne $file.sha256) { throw "Staged file hash mismatch: $path" }
            [pscustomobject]@{ name = $file.name; sha256 = $hash; status = $status }
        })
    }
    finally { $sha.Dispose() }
    [pscustomobject]@{
        kind = 'uls-lab-files-staged'
        folder = $folder
        files = $results
    } | ConvertTo-Json -Depth 4
}
'@
$payload = $template.Replace('__LAB_FILES__', $manifest)
if ($PSCmdlet.ShouldProcess($output, 'Write text-transfer payload for the two synthetic lab setup files')) {
    $handle = [IO.File]::Open($output, 'CreateNew', 'Write', 'None')
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($payload)
        $handle.Write($bytes, 0, $bytes.Length)
    }
    finally { $handle.Dispose() }
    Write-Host 'Generated locally only. Review and transfer the text into the approved lab VM; no Azure call was made.'
    Write-Host 'The payload stages files only. Run the initializer separately under the approved signing policy.'
    [pscustomobject]@{
        outputPath = $output
        guestFolder = 'C:\Temp\SP-LabSetup'
        files = @($files | Select-Object name, sha256)
    }
}

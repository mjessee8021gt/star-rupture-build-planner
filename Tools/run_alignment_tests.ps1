$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$resultPath = Join-Path $PSScriptRoot "alignment_test_result.txt"
Push-Location $projectRoot
try {
    if (Test-Path $resultPath) {
        Remove-Item -LiteralPath $resultPath -Force
    }

    $godotCommand = Get-Command godot.exe -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) {
        $godotCommand = Get-Command godot -ErrorAction Stop
    }

    $godotPath = $godotCommand.Source
    $toolsPath = Join-Path (Split-Path $godotPath) "godot.windows.opt.tools.64.exe"
    if (Test-Path $toolsPath) {
        $godotPath = $toolsPath
    }

    & $godotPath --headless --path . --script "res://Tools/test_alignment.gd" | Out-Null

    if (-not (Test-Path $resultPath)) {
        Write-Host "Alignment smoke tests did not produce a result file."
        exit 1
    }

    $resultText = Get-Content -LiteralPath $resultPath -Raw
    Write-Host $resultText.Trim()

    if ($resultText -match "passed") {
        exit 0
    } else {
        exit 1
    }
}
finally {
    Pop-Location
}

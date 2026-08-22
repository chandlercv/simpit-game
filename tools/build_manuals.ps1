<#
.SYNOPSIS
  Build PDF copies of the ship's two documents.

.DESCRIPTION
  Two steps, because Godot has no PDF writer:

    1. `ManualExport.tscn` renders both chapter catalogs to print-styled HTML,
       resolving the binding placeholders through the real ManualViewer so the
       printed page names the same controls the in-game page does.
    2. A headless Chromium browser prints that HTML to PDF.

  Everything lands in build/manuals, which is gitignored. These are build
  outputs: the two catalogs are the source of truth, and a committed PDF would
  be a third in-tree copy of every figure in them.

.PARAMETER OutDir
  Where to write, relative to the project root. Default build/manuals.

.PARAMETER HtmlOnly
  Skip the PDF step. Useful when no Chromium browser is installed, or when you
  only want to eyeball the markup.

.EXAMPLE
  pwsh tools/build_manuals.ps1
#>
[CmdletBinding()]
param(
    [string] $OutDir = 'build/manuals',
    [switch] $HtmlOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$absoluteOut = Join-Path $projectRoot $OutDir

# --- 1. Godot: catalogs -> HTML ---------------------------------------------
# godot_console.exe first: the plain godot.exe is a GUI-subsystem binary, so it
# detaches and leaves $LASTEXITCODE unset even on a clean run.
$godot = @('godot_console', 'godot') |
    ForEach-Object { (Get-Command $_ -ErrorAction SilentlyContinue).Source } |
    Where-Object { $_ } | Select-Object -First 1
if (-not $godot) { throw "godot is not on PATH. Install Godot 4.7 and retry." }

Write-Host "Rendering both documents to HTML..."
& $godot --headless --path $projectRoot 'res://tools/ManualExport.tscn' '++' $OutDir

# Judge the step by what it produced rather than by the exit code, which the
# GUI-subsystem build does not reliably set.
$html = @(Get-ChildItem -Path $absoluteOut -Filter '*.html' -ErrorAction SilentlyContinue)
if ($html.Count -eq 0) { throw "ManualExport wrote no HTML to $absoluteOut." }

if ($HtmlOnly) {
    Write-Host "HTML only, as requested. Files are in $absoluteOut"
    return
}

# --- 2. Headless Chromium: HTML -> PDF ---------------------------------------
# Any Chromium will do; Edge ships with Windows, so the fallback is not exotic.
$candidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)
$browser = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) {
    Write-Warning "No Chrome or Edge found — stopping after the HTML step."
    Write-Warning "Files are in $absoluteOut; print them from any browser, or re-run with -HtmlOnly."
    return
}

# A throwaway profile, so the print never hands off to a Chrome the user already
# has open — which is what makes the run non-deterministic otherwise.
$profileDir = Join-Path ([System.IO.Path]::GetTempPath()) "salvager-manual-print-$PID"

try {
    foreach ($doc in $html) {
        $pdf = [System.IO.Path]::ChangeExtension($doc.FullName, '.pdf')
        Remove-Item $pdf -ErrorAction SilentlyContinue
        Write-Host "Printing $($doc.Name) -> $(Split-Path -Leaf $pdf)"
        & $browser --headless=new --disable-gpu --no-pdf-header-footer `
            "--user-data-dir=$profileDir" `
            "--print-to-pdf=$pdf" "file:///$($doc.FullName -replace '\\', '/')" 2>$null

        # The browser returns before the file is flushed, so wait for the size to
        # settle rather than trusting the call to have finished the job.
        $lastSize = -1
        $stable = 0
        for ($i = 0; $i -lt 120; $i++) {
            Start-Sleep -Milliseconds 250
            if (-not (Test-Path $pdf)) { continue }
            $size = (Get-Item $pdf).Length
            if ($size -gt 0 -and $size -eq $lastSize) {
                $stable++
                if ($stable -ge 2) { break }
            } else {
                $stable = 0
            }
            $lastSize = $size
        }
        if (-not (Test-Path $pdf) -or (Get-Item $pdf).Length -eq 0) {
            throw "Browser produced no PDF for $($doc.Name)."
        }
    }
} finally {
    Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Done. PDFs are in $absoluteOut"

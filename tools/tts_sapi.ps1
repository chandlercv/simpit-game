<#
.SYNOPSIS
  Render a batch of speech clips to WAV with the Windows SAPI voices.

.DESCRIPTION
  The raw-voice stage of tools/build_speech.py, and deliberately the ONLY part
  of the pipeline that knows what a text-to-speech engine is. Everything
  downstream - the radio treatment, the concatenation manifest, the runtime -
  works on WAV files and does not care where they came from.

  That separation is the point. Audio rendered from the Windows voices is
  licence-grey to redistribute (the Windows terms grant you their use, not the
  right to ship their output inside another product), so the bank in
  assets/generated/voice/ is flagged in CREDITS.md as the folder to re-render
  before any commercial release. Re-rendering means pointing build_speech.py at
  a different engine - `--engine wavdir`, or a sibling of this script - and
  running it again. Nothing else in the project changes.

.PARAMETER JobFile
  JSON array of { voice, rate, text, out }. Written by build_speech.py.

.EXAMPLE
  pwsh tools/tts_sapi.ps1 -JobFile build/speech/jobs.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $JobFile
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech

$jobs = Get-Content -Raw -Path $JobFile | ConvertFrom-Json
if ($jobs.Count -eq 0) { Write-Host "Nothing to render."; return }

# One synthesiser per voice rather than per clip: constructing it is by far the
# most expensive thing here, and there are only three voices across hundreds of
# clips.
$synths = @{}

# 22.05 kHz mono is already generous for speech that is about to be band-limited
# to a radio channel; the encoder downstream decides the shipped size.
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    22050,
    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)

$done = 0
try {
    foreach ($job in $jobs) {
        if (-not $synths.ContainsKey($job.voice)) {
            $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
            try {
                $s.SelectVoice($job.voice)
            } catch {
                # The OneCore voices are not always renderable to a file. Say so
                # once, loudly, rather than emitting silence nobody notices.
                throw "Voice '$($job.voice)' is not available for file rendering. Installed: " +
                      (($s.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }) -join ', ')
            }
            $synths[$job.voice] = $s
        }
        $synth = $synths[$job.voice]
        $synth.Rate = [int]$job.rate

        $dir = Split-Path -Parent $job.out
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

        $synth.SetOutputToWaveFile($job.out, $fmt)
        $synth.Speak($job.text)
        $synth.SetOutputToNull()

        $done++
        if ($done % 50 -eq 0) { Write-Host "  rendered $done / $($jobs.Count)" }
    }
} finally {
    foreach ($s in $synths.Values) { $s.Dispose() }
}

Write-Host "Rendered $done clips."

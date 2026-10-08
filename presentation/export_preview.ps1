# Export the current illustrated deck using desktop PowerPoint on Windows.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$deckPath = Join-Path $PSScriptRoot 'Reach-developer-presentation-storybook.pptx'
$pdfPath = Join-Path $PSScriptRoot 'Reach-developer-presentation-storybook.pdf'
$previewPath = Join-Path $PSScriptRoot 'storybook-preview'
New-Item -ItemType Directory -Path $previewPath -Force | Out-Null

# Leave an existing interactive PowerPoint session running.
$wasRunning = @(Get-Process POWERPNT -ErrorAction SilentlyContinue).Count -gt 0
$powerPoint = $null
$deck = $null
try {
    $powerPoint = New-Object -ComObject PowerPoint.Application
    # ReadOnly, Untitled, WithWindow: export without displaying a document window.
    $deck = $powerPoint.Presentations.Open($deckPath, $true, $false, $false)
    $deck.SaveAs($pdfPath, 32) # ppSaveAsPDF
    $deck.Export($previewPath, 'PNG', 1600, 900)
    Write-Output ("Exported {0} slides to {1} and {2}" -f $deck.Slides.Count, $pdfPath, $previewPath)
}
finally {
    if ($null -ne $deck) {
        $deck.Close()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($deck)
    }
    if ($null -ne $powerPoint) {
        if (-not $wasRunning) { $powerPoint.Quit() }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($powerPoint)
    }
}

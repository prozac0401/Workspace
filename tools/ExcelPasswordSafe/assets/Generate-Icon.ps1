#requires -Version 5.1
<#
Rebuild the original vector app icon with Windows' built-in WPF renderer.
Run with Windows PowerShell 5.1 -STA. No downloaded fonts or graphics packages.
The SVG and every ICO/PNG frame use the same 64-unit paths and colors below.
Only the requested output files are replaced; no directories are deleted.
#>
[CmdletBinding()]
param([string]$OutputDirectory)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Run with powershell.exe -STA.' }
Add-Type -AssemblyName WindowsBase, PresentationCore, PresentationFramework
if (-not $OutputDirectory) { $OutputDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$shackle = 'M18 28 V20 C18 12.268 24.268 6 32 6 C39.732 6 46 12.268 46 20 V28 H39 V20 C39 16.134 35.866 13 32 13 C28.134 13 25 16.134 25 20 V28 Z'
$body = 'M16 26 H48 C52.418 26 56 29.582 56 34 V50 C56 54.418 52.418 58 48 58 H16 C11.582 58 8 54.418 8 50 V34 C8 29.582 11.582 26 16 26 Z'
$keyhole = 'M32 35 C28.962 35 26.5 37.462 26.5 40.5 C26.5 42.536 27.606 44.314 29.25 45.265 L28.5 49 H35.5 L34.75 45.265 C36.394 44.314 37.5 42.536 37.5 40.5 C37.5 37.462 35.038 35 32 35 Z'
$slate = '#687BA8'
$indigoTop = '#526FE9'
$indigoBottom = '#3454CC'
$white = '#FFFFFF'
$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 64 64" role="img" aria-labelledby="title">
  <title id="title">Excel Password Safe padlock</title>
  <defs>
    <linearGradient id="body" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="$indigoTop"/>
      <stop offset="1" stop-color="$indigoBottom"/>
    </linearGradient>
  </defs>
  <path fill="$slate" d="$shackle"/>
  <path fill="url(#body)" d="$body"/>
  <path fill="$white" d="$keyhole"/>
</svg>
"@
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'ExcelPasswordSafe.svg'), $svg + "`n", [Text.UTF8Encoding]::new($false))

$shackleGeometry = [Windows.Media.Geometry]::Parse($shackle)
$bodyGeometry = [Windows.Media.Geometry]::Parse($body)
$keyholeGeometry = [Windows.Media.Geometry]::Parse($keyhole)
$slateBrush = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($slate))
$bodyBrush = [Windows.Media.LinearGradientBrush]::new(
    [Windows.Media.ColorConverter]::ConvertFromString($indigoTop),
    [Windows.Media.ColorConverter]::ConvertFromString($indigoBottom),
    [Windows.Point]::new(0, 0), [Windows.Point]::new(1, 1))
$whiteBrush = [Windows.Media.Brushes]::White
foreach ($resource in @($shackleGeometry,$bodyGeometry,$keyholeGeometry,$slateBrush,$bodyBrush)) { $resource.Freeze() }

function Render-Icon([int]$Size) {
    $visual = [Windows.Media.DrawingVisual]::new()
    $context = $visual.RenderOpen()
    try {
        $context.PushTransform([Windows.Media.ScaleTransform]::new($Size / 64.0, $Size / 64.0))
        $context.DrawGeometry($slateBrush, $null, $shackleGeometry)
        $context.DrawGeometry($bodyBrush, $null, $bodyGeometry)
        $context.DrawGeometry($whiteBrush, $null, $keyholeGeometry)
        $context.Pop()
    } finally { $context.Close() }
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new($Size, $Size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $bitmap.Freeze()
    return $bitmap
}

function Png-Bytes([Windows.Media.Imaging.BitmapSource]$Bitmap) {
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
    $stream = [IO.MemoryStream]::new()
    try { $encoder.Save($stream); return ,$stream.ToArray() } finally { $stream.Dispose() }
}

$sizes = @(16,20,24,32,40,48,64,128,256)
$frames = @()
foreach ($size in $sizes) {
    $bitmap = Render-Icon $size
    $frames += [pscustomobject]@{Size=$size; Bitmap=$bitmap; Bytes=(Png-Bytes $bitmap)}
}
# Windows Vista and later support PNG images in ICO resources. Store every
# requested frame at its native pixel size, with 32-bit RGBA and transparency.
$iconStream = [IO.MemoryStream]::new()
$writer = [IO.BinaryWriter]::new($iconStream)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    foreach ($frame in $frames) {
        $dimension = [byte]$(if ($frame.Size -eq 256) { 0 } else { $frame.Size })
        $writer.Write($dimension); $writer.Write($dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
    $writer.Flush()
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'ExcelPasswordSafe.ico'), $iconStream.ToArray())
} finally { $writer.Dispose(); $iconStream.Dispose() }
[IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'ExcelPasswordSafe.png'), $frames[-1].Bytes)

# Preview the 256px master plus native-size frames on both light and dark UI.
$preview = [Windows.Media.DrawingVisual]::new()
$drawing = $preview.RenderOpen()
try {
    $light = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#F5F7FC'))
    $dark = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#172136'))
    $muted = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#52637F'))
    $drawing.DrawRectangle($light, $null, [Windows.Rect]::new(0,0,800,360))
    $drawing.DrawImage($frames[-1].Bitmap, [Windows.Rect]::new(24,32,256,256))
    $drawing.DrawRectangle($dark, $null, [Windows.Rect]::new(312,180,464,156))
    $x = 328.0
    foreach ($frame in $frames[0..6]) {
        $size = $frame.Size
        $drawing.DrawImage($frame.Bitmap, [Windows.Rect]::new($x + (64-$size)/2.0,104-$size/2.0,$size,$size))
        $drawing.DrawImage($frame.Bitmap, [Windows.Rect]::new($x + (64-$size)/2.0,252-$size/2.0,$size,$size))
        $label = [Windows.Media.FormattedText]::new([string]$size, [Globalization.CultureInfo]::InvariantCulture, [Windows.FlowDirection]::LeftToRight,
            [Windows.Media.Typeface]::new('Segoe UI'), 12.0, $muted, 1.0)
        $drawing.DrawText($label, [Windows.Point]::new($x + (64-$label.Width)/2.0,150))
        $x += 64
    }
} finally { $drawing.Close() }
$previewBitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(800,360,96,96,[Windows.Media.PixelFormats]::Pbgra32)
$previewBitmap.Render($preview)
[IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'ExcelPasswordSafe.preview.png'), (Png-Bytes $previewBitmap))
[pscustomobject]@{Icon=(Join-Path $OutputDirectory 'ExcelPasswordSafe.ico'); Frames=$sizes; Preview=(Join-Path $OutputDirectory 'ExcelPasswordSafe.preview.png')}

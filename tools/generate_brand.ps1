Add-Type -AssemblyName System.Drawing
$brandRoot = Split-Path -Parent $PSScriptRoot
function New-BrandPng([int]$size, [string]$path) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(246,247,249))
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(35,75,128))
    $points = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($size*.2,$size*.18),
        [System.Drawing.PointF]::new($size*.46,$size*.43),
        [System.Drawing.PointF]::new($size*.54,$size*.43),
        [System.Drawing.PointF]::new($size*.8,$size*.18),
        [System.Drawing.PointF]::new($size*.76,$size*.66),
        [System.Drawing.PointF]::new($size*.5,$size*.87),
        [System.Drawing.PointF]::new($size*.24,$size*.66))
    $graphics.FillPolygon($brush,$points)
    $graphics.FillEllipse([System.Drawing.Brushes]::White,[single]($size*.36),[single]($size*.59),[single]($size*.05),[single]($size*.05))
    $graphics.FillEllipse([System.Drawing.Brushes]::White,[single]($size*.59),[single]($size*.59),[single]($size*.05),[single]($size*.05))
    $bitmap.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $brush.Dispose(); $bitmap.Dispose()
}
$densities = @{ 'mdpi'=48; 'hdpi'=72; 'xhdpi'=96; 'xxhdpi'=144; 'xxxhdpi'=192 }
foreach ($density in $densities.Keys) {
    New-BrandPng $densities[$density] (Join-Path $brandRoot "android/app/src/main/res/mipmap-$density/ic_launcher.png")
}
$pngPath = Join-Path $brandRoot 'assets/brand.png'
New-BrandPng 256 $pngPath
$png = [System.IO.File]::ReadAllBytes($pngPath)
$stream = [System.IO.File]::Create((Join-Path $brandRoot 'windows/runner/resources/app_icon.ico'))
$writer = [System.IO.BinaryWriter]::new($stream)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
$writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
$writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$png.Length); $writer.Write([uint32]22)
$writer.Write($png); $writer.Dispose(); $stream.Dispose()

Add-Type -AssemblyName System.Drawing
$w=640; $h=480
$bmp = New-Object System.Drawing.Bitmap($w,$h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode='AntiAlias'
$g.TextRenderingHint='AntiAliasGridFit'

# black ground
$g.Clear([System.Drawing.Color]::FromArgb(255,10,8,6))

# silk-like gold sweeps
for($i=0;$i -lt 5;$i++){
  $alpha = 14 + $i*4
  $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0,0)),(New-Object System.Drawing.Point($w,$h)),
    [System.Drawing.Color]::FromArgb($alpha,212,168,96),[System.Drawing.Color]::FromArgb(0,0,0,0))
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $x0 = 320 + $i*70 - 140
  $path.AddClosedCurve(@(
    (New-Object System.Drawing.Point(($x0+60),-40)),
    (New-Object System.Drawing.Point(($x0-40),160)),
    (New-Object System.Drawing.Point(($x0+30),360)),
    (New-Object System.Drawing.Point(($x0-60),520)),
    (New-Object System.Drawing.Point(($x0+150),520)),
    (New-Object System.Drawing.Point(($x0+180),200)),
    (New-Object System.Drawing.Point(($x0+170),-40))
  ))
  $g.FillPath($br,$path)
  $br.Dispose(); $path.Dispose()
}

# gold gradient text
function Draw-GoldLine($g,$text,$y,$size){
  $font = New-Object System.Drawing.Font('Arial',$size,[System.Drawing.FontStyle]::Bold)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment='Center'
  $rect = New-Object System.Drawing.RectangleF(0,$y,640,($size*1.6))
  # shadow
  $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180,0,0,0))
  $shRect = New-Object System.Drawing.RectangleF(3,($y+4),640,($size*1.6))
  $g.DrawString($text,$font,$sh,$shRect,$fmt)
  # gold gradient
  $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0,[int]$y)),(New-Object System.Drawing.Point(0,[int]($y+$size*1.4))),
    [System.Drawing.Color]::FromArgb(255,246,222,160),[System.Drawing.Color]::FromArgb(255,138,100,38))
  $g.DrawString($text,$font,$gb,$rect,$fmt)
  $font.Dispose(); $sh.Dispose(); $gb.Dispose(); $fmt.Dispose()
}
Draw-GoldLine $g 'FILIPINO' 96 62
Draw-GoldLine $g 'MUSIC'    186 62
Draw-GoldLine $g 'AWARDS'   276 62

# footer line
$f2 = New-Object System.Drawing.Font('Arial',15,[System.Drawing.FontStyle]::Regular)
$fmt2 = New-Object System.Drawing.StringFormat; $fmt2.Alignment='Center'
$b2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210,214,178,116))
$mid=[string][char]183
$g.DrawString("OCTOBER 21, 2026  $mid  MALL OF ASIA ARENA",$f2,$b2,(New-Object System.Drawing.RectangleF(0,398,640,30)),$fmt2)

$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object {$_.MimeType -eq 'image/jpeg'}
$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]72)
$out = Join-Path $PSScriptRoot 'fma.jpg'
$bmp.Save($out,$enc,$ep)
$g.Dispose(); $bmp.Dispose()
(Get-Item $out).Length

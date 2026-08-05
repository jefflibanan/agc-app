param([string]$Url,[string]$Out)
$tmp = "$env:TEMP\fr_dl.png"
Invoke-WebRequest -Uri $Url -OutFile $tmp
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($tmp)
$w = 640; $h = [int]($img.Height * ($w / $img.Width))
$bmp = New-Object System.Drawing.Bitmap($w,$h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($img,0,0,$w,$h)
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object {$_.MimeType -eq 'image/jpeg'}
$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]62)
$bmp.Save($Out,$enc,$ep)
$g.Dispose(); $bmp.Dispose(); $img.Dispose()
Remove-Item $tmp -Force
(Get-Item $Out).Length

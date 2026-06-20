Add-Type -AssemblyName System.Drawing
$img_path = 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png'
if (Test-Path $img_path) {
    $img = [System.Drawing.Image]::FromFile($img_path)
    $bmp = new-object System.Drawing.Bitmap($img)
    $corner = $bmp.GetPixel(0,0)
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $pixel = $bmp.GetPixel($x, $y)
            if ($pixel.R -eq $corner.R -and $pixel.G -eq $corner.G -and $pixel.B -eq $corner.B) {
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
            } else {
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 255, 255, 255))
            }
        }
    }
    $out_dir = 'android/app/src/main/res/drawable'
    if (-not (Test-Path $out_dir)) { New-Item -ItemType Directory -Path $out_dir }
    $bmp.Save("$out_dir/ic_notification.png", [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host 'Created ic_notification.png'
} else {
    Write-Host 'Image not found'
}

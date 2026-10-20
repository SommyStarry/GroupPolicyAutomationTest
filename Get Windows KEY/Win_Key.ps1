function Get-WindowsKeys {
    Write-Host "`n========== ПЕРЕВІРКА КЛЮЧІВ WINDOWS ==========" -ForegroundColor Cyan

    # --- OEM ключ із BIOS ---
    $biosKey = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
    if ($biosKey) {
        Write-Host "OEM ключ з BIOS/UEFI знайдено:" -ForegroundColor Green
        Write-Host "    $biosKey"
    } else {
        Write-Host "OEM ключ у BIOS не знайдено." -ForegroundColor Yellow
    }

    # --- Ключ із реєстру ---
    $hklm = 2147483650
    $key = "SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($hklm, "")
    $subKey = $reg.OpenSubKey($key)
    $value = $subKey.GetValue("DigitalProductId")

    if (-not $value) {
        Write-Host "Не вдалося отримати DigitalProductId з реєстру." -ForegroundColor Red
        return
    }

    function Decode-Key {
        param([byte[]]$DigitalProductId)
        $keyOffset = 52
        $chars = "BCDFGHJKMPQRTVWXY2346789"
        $isWin8OrUp = ($DigitalProductId[66] -band 0xF0) -eq 0xF0

        if ($isWin8OrUp) {
            return $null
        }

        $key = ""
        for ($i = 24; $i -ge 0; $i--) {
            $cur = 0
            for ($j = 14; $j -ge 0; $j--) {
                $cur = ($cur * 256) -bxor $DigitalProductId[$j + $keyOffset]
                $DigitalProductId[$j + $keyOffset] = [math]::Floor($cur / 24)
                $cur = $cur % 24
            }
            $key = $chars[$cur] + $key
            if (($i % 5) -eq 0 -and $i -ne 0) {
                $key = "-" + $key
            }
        }
        return $key
    }

    $decodedKey = Decode-Key $value

    if ($decodedKey) {
        Write-Host "Ключ з реєстру (може бути введений вручну):" -ForegroundColor Green
        Write-Host "    $decodedKey"
    } else {
        Write-Host "Ключ з реєстру неможливо розшифрувати — імовірно, Windows 8 або новіше з OEM ключем у BIOS." -ForegroundColor Yellow
    }

    Write-Host "`n==============================================" -ForegroundColor Cyan
}

# Запуск
Get-WindowsKeys
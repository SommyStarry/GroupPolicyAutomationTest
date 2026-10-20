# Отримання інформації про систему
$os = Get-CimInstance Win32_OperatingSystem
$osVersion = $os.Caption
$osBuild = $os.BuildNumber
$installDate = $os.InstallDate
$licenseKey = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
$winRelease = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DisplayVersion" | Select-Object -ExpandProperty DisplayVersion
$computerSerial = (Get-CimInstance Win32_BIOS).SerialNumber
$motherboard = Get-CimInstance Win32_BaseBoard
$mbName = $motherboard.Product
$mbSerial = $motherboard.SerialNumber
$ram = Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer, Capacity, SerialNumber
$disks = Get-CimInstance Win32_DiskDrive | Select-Object Model, Size, SerialNumber
$networkAdapters = Get-CimInstance Win32_NetworkAdapter | Where-Object {
    $_.NetConnectionID -match "Ethernet|Wi-Fi|Wireless" -or $_.Name -match "Ethernet|Wi-Fi|Wireless"
} | Where-Object { 
    # Виключаємо адаптери, у яких є "Virtual" у назві або адаптери VMware
    $_.Name -notmatch "Virtual|VMware" 
} | Select-Object Name, MACAddress, NetEnabled, NetConnectionStatus
$videoAdapter = Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM
$processor = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores
$hostname = (Get-CimInstance Win32_ComputerSystem).Name
$manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer

# Отримання інформації про Bluetooth адаптери
$bluetoothAdapters = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.Name -like "*Bluetooth*" } | Select-Object Name, MACAddress

# Визначення шляхів до файлів
# $csvFile = ".\System_Info.csv"
$textFile = ".\$manufacturer - $computerSerial.txt"

<# Формування CSV
$data = @()
$data += "Hostname,$hostname"
$data += "Виробник,$manufacturer"
$data += "Серійний номер комп'ютера,$computerSerial"
$data += "Назва ОС,$osVersion"
$data += "Версія збірки Windows,$winRelease"
$data += "Збірка ОС,$osBuild"
$data += "Дата встановлення,$installDate"
$data += "Ключ ліцензії,$licenseKey"
$data += "Материнська плата,$mbName"
$data += "Серійний номер материнської плати,$mbSerial"

$data += "Процесор"
foreach ($cpu in $processor) {
    $data += "Процесор,$($cpu.Name)"
    $data += "Кількість ядер,$($cpu.NumberOfCores)"
}

$data += "Відеоадаптер"
foreach ($adapter in $videoAdapter) {
    $data += "Відео адаптер,$($adapter.Name)"
    $data += "Ємність відео пам'яті,$([math]::Round($adapter.AdapterRAM / 1MB, 2)) MB"
}

$data += "Оперативна пам’ять"
foreach ($r in $ram) {
    $data += "ОЗП Виробник,$($r.Manufacturer)"
    $data += "ОЗП Ємність,$([math]::Round($r.Capacity / 1GB, 2)) GB"
    $data += "ОЗП Серійний номер,$($r.SerialNumber)"
    $data += ""
}

$data += "HDD/SSD накопичувачі"
foreach ($disk in $disks) {
    $data += "Диск Модель,$($disk.Model)"
    $data += "Диск Ємність,$([math]::Round($disk.Size / 1GB, 2)) GB"
    $data += "Диск Серійний номер,$($disk.SerialNumber)"
    $data +=""
}

$data += "Мережеві адаптери"
foreach ($adapter in $networkAdapters) {
    $mac = if ($adapter.MACAddress) { $adapter.MACAddress } else { "Немає MAC-адреси" }
    $data += "Мережевий адаптер,$($adapter.Name)"
    $data += "MAC-адреса,$mac"
    $data +=" "
}

# Інформація про Bluetooth адаптери
$data += "Bluetooth адаптери"
foreach ($adapter in $bluetoothAdapters) {
    $macAddress = if ($adapter.MACAddress) { $adapter.MACAddress } else { "Немає MAC-адреси" }
    $data += "Bluetooth адаптер,$($adapter.Name)"
    $data += "MAC-адреса Bluetooth,$macAddress"
}

$data += ""  # Порожній рядок для відділення записів

# Запис у CSV
$data | Out-File -Encoding UTF8 -Append -FilePath $csvFile

#>

# Формування структурованого тексту
$textOutput = @()
$textOutput += "`n"  # Додає порожній рядок перед новим блоком
$textOutput += "========== ЗВІТ ПРО СИСТЕМУ =========="
$textOutput += "== $manufacturer - $computerSerial =="
$textOutput += ""
$textOutput += "== ОСНОВНА ІНФОРМАЦІЯ =="
$textOutput += "Hostname: $hostname"
$textOutput += "Виробник: $manufacturer"
$textOutput += "Серійний номер комп'ютера: $computerSerial"
$textOutput += "Назва ОС: $osVersion"
$textOutput += "Версія збірки Windows: $winRelease"
$textOutput += "Збірка ОС: $osBuild"
$textOutput += "Дата встановлення: $installDate"
$textOutput += "Ключ ліцензії: $licenseKey"
$textOutput += "Материнська плата: $mbName"
$textOutput += "Серійний номер материнської плати: $mbSerial"
$textOutput += ""

$textOutput += "== ПРОЦЕСОР =="
foreach ($cpu in $processor) {
    $textOutput += "Процесор: $($cpu.Name)"
    $textOutput += "Кількість ядер: $($cpu.NumberOfCores)"
}
$textOutput += ""

$textOutput += "== ВІДЕОАДАПТЕР =="
foreach ($adapter in $videoAdapter) {
    $textOutput += "Назва: $($adapter.Name)"
    $textOutput += "Відеопам’ять: $([math]::Round($adapter.AdapterRAM / 1MB, 2)) MB"
}

$textOutput += ""

$textOutput += "== ОПЕРАТИВНА ПАМ’ЯТЬ =="
foreach ($r in $ram) {
    $textOutput += "Виробник: $($r.Manufacturer)"
    $textOutput += "Обсяг: $([math]::Round($r.Capacity / 1GB, 2)) GB"
    $textOutput += "Серійний номер: $($r.SerialNumber)"
    $textOutput += ""
}

$textOutput += "== HDD / SSD =="
foreach ($disk in $disks) {
    $textOutput += "Модель: $($disk.Model)"
    $textOutput += "Обсяг: $([math]::Round($disk.Size / 1GB, 2)) GB"
    $textOutput += "Серійний номер: $($disk.SerialNumber)"
    $textOutput += ""
}

$textOutput += "== МЕРЕЖЕВІ АДАПТЕРИ =="
foreach ($adapter in $networkAdapters) {
    $mac = if ($adapter.MACAddress) { $adapter.MACAddress } else { "Немає MAC-адреси" }
    $textOutput += "Адаптер: $($adapter.Name)"
    $textOutput += "MAC-адреса: $mac"
    $textOutput += ""
}

$textOutput += "== BLUETOOTH АДАПТЕРИ =="
foreach ($adapter in $bluetoothAdapters) {
    $macAddress = if ($adapter.MACAddress) { $adapter.MACAddress } else { "Немає MAC-адреси" }
    $textOutput += "Bluetooth адаптер: $($adapter.Name)"
    $textOutput += "MAC-адреса Bluetooth: $macAddress"
}
$textOutput += ""

# Вивід у консоль
$textOutput -join "`n" | Write-Host -ForegroundColor Green

# Запис у .txt файл
$textOutput | Out-File -Encoding UTF8 -Append -FilePath $textFile

Write-Host "Інформація збережена у файли:"
# Write-Host "`n - CSV: $csvFile"
Write-Host " - TXT: $textFile"

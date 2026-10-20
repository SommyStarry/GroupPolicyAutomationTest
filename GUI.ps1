param(
    # Службовий параметр: зберегти знімки всіх вкладок у вказану папку та вийти (для перевірки вигляду)
    [string]$Screenshot
)

# ---------------------------------------------------------------------------------------------
# GroupPolicyAutomation GUI - інформаційна панель для системних адміністраторів.
# Нічого не змінює в системі: лише показує стан і доступні конфігурації.
# Застосування налаштувань - через кнопку, що відкриває консольне меню Config.ps1.
# ---------------------------------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type -Namespace Native -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    [void][Native.Dpi]::SetProcessDPIAware()
} catch {}
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = $PSScriptRoot
$script:Colors = @{
    OK   = [System.Drawing.Color]::FromArgb(230, 244, 234)
    WARN = [System.Drawing.Color]::FromArgb(255, 244, 206)
    FAIL = [System.Drawing.Color]::FromArgb(253, 231, 233)
    INFO = [System.Drawing.Color]::White
}
$script:Mark = @{ OK = [string][char]0x2714 + " ОК"; WARN = [string][char]0x26A0 + " Увага"; FAIL = [string][char]0x2716 + " Помилка"; INFO = [string][char]0x2139 + " Інфо" }

# ======================================================================= ЗБІР ДАНИХ

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Та сама логіка, що й CheckWinVersion у Config.ps1
function Get-WinFamily {
    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if ($build -ge 22000) { return "Windows 11" }
    elseif ($build -ge 10240) { return "Windows 10" }
    else { return "Unknown" }
}

function Format-Size([double]$bytes) {
    if ($bytes -ge 1TB) { return ("{0:N2} ТБ" -f ($bytes / 1TB)) }
    if ($bytes -ge 1GB) { return ("{0:N1} ГБ" -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ("{0:N1} МБ" -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ("{0:N0} КБ" -f ($bytes / 1KB)) }
    return ("{0:N0} Б" -f $bytes)
}

function Test-PendingReboot {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return $true }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return $true }
    $p = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    return [bool]$p.PendingFileRenameOperations
}

# Таблиці
function New-Table([string[]]$cols) {
    $dt = New-Object System.Data.DataTable
    foreach ($c in $cols) { [void]$dt.Columns.Add($c) }
    [void]$dt.Columns.Add('_st')
    return ,$dt
}
function Add-Row($dt, [object[]]$values, [string]$status = 'INFO') {
    [void]$dt.Rows.Add([object[]]($values + $status))
}

$script:T = [ordered]@{
    Overview = New-Table @('Перевірка', 'Результат', 'Деталі')
    Disks    = New-Table @('Диск', 'Назва', 'Тип', 'ФС', 'Обсяг', 'Вільно', 'Заповнено', 'Роль у скрипті', 'Стан')
    Phys     = New-Table @('Модель', 'Тип носія', 'Шина', 'Обсяг', 'Стан здоров''я')
    Configs  = New-Table @('Збірка', 'Папка Configs', 'ОС', 'Пункт меню', 'Підходить цьому ПК', 'Дата копії', 'Machine', 'User', 'audit.csv', 'GptTmpl.inf')
    Services = New-Table @('Служба', 'Назва', 'Поточний', 'Цільовий', 'Результат')
    Settings = New-Table @('Категорія', 'Параметр', 'Поточне', 'Цільове', 'Результат')
    Files    = New-Table @('Файл', 'Розмір', 'Змінено', 'SHA-256 (початок)')
}

function Fill-Overview {
    $dt = $script:T.Overview; $dt.Clear()
    $isAdmin = Test-IsAdmin
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $family = Get-WinFamily
    $disp = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion

    if ($isAdmin) { Add-Row $dt @('Права адміністратора', $script:Mark.OK, 'Скрипт запущено з підвищеними правами.') 'OK' }
    else { Add-Row $dt @('Права адміністратора', $script:Mark.FAIL, 'Config.ps1 потребує прав адміністратора. Скористайтесь кнопкою «Перезапустити від адміністратора».') 'FAIL' }

    if ($family -eq 'Unknown') { Add-Row $dt @('Версія ОС', $script:Mark.FAIL, "$($os.Caption), збірка $($os.BuildNumber): не підтримується (потрібна Windows 10 або 11).") 'FAIL' }
    else { Add-Row $dt @('Версія ОС', $script:Mark.OK, "$($os.Caption) $disp, збірка $($os.BuildNumber) - буде використано набір для $family.") 'OK' }

    $psv = $PSVersionTable.PSVersion
    if ($psv.Major -ge 5) { Add-Row $dt @('Windows PowerShell', $script:Mark.OK, "Версія $psv") 'OK' }
    else { Add-Row $dt @('Windows PowerShell', $script:Mark.WARN, "Версія $psv; рекомендовано 5.1.") 'WARN' }

    if ($cs.PartOfDomain) { Add-Row $dt @('Домен', $script:Mark.WARN, "ПК у домені $($cs.Domain): доменні GPO мають пріоритет над локальними політиками, що застосовує LGPO.") 'WARN' }
    else { Add-Row $dt @('Домен', $script:Mark.OK, "Робоча група $($cs.Domain): локальні політики не перекриваються доменними.") 'OK' }

    foreach ($f in @(
        @{ N = 'Config.ps1'; D = 'Основний скрипт' },
        @{ N = 'LGPO.exe'; D = 'Утиліта імпорту політик' },
        @{ N = 'AppLocker_Policy.xml'; D = 'Політика AppLocker' },
        @{ N = 'Configs\LGPO-Default\LGPO-Default-Security-Settings.inf'; D = 'Стандартні Security Settings (для відкату)' })) {
        if (Test-Path (Join-Path $script:Root $f.N)) { Add-Row $dt @($f.N, $script:Mark.OK, $f.D) 'OK' }
        else { Add-Row $dt @($f.N, $script:Mark.FAIL, "Файл не знайдено: $($f.D)") 'FAIL' }
    }

    $missing = @($script:Builds | Where-Object { -not (Test-Path (Join-Path $script:Root "Configs\$($_.Folder)")) })
    if ($missing.Count -eq 0) { Add-Row $dt @('Папки збірок (Configs)', $script:Mark.OK, "Знайдено всі $($script:Builds.Count) збірок.") 'OK' }
    else { Add-Row $dt @('Папки збірок (Configs)', $script:Mark.FAIL, "Відсутні: $(($missing | ForEach-Object { $_.Folder }) -join ', ')") 'FAIL' }

    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'" -ErrorAction SilentlyContinue
    if ($d) { Add-Row $dt @('Диск D:', $script:Mark.OK, "Є, вільно $(Format-Size $d.FreeSpace). Сюди буде перенесено профілі користувачів.") 'OK' }
    else { Add-Row $dt @('Диск D:', $script:Mark.WARN, 'Не знайдено. Зміна шляху профілів буде пропущена (D:\Користувачі).') 'WARN' }

    $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    if ($c) {
        if ($c.FreeSpace -lt 15GB) { Add-Row $dt @('Вільне місце на C:', $script:Mark.WARN, "Вільно $(Format-Size $c.FreeSpace); для точок відновлення резервується 10 ГБ.") 'WARN' }
        else { Add-Row $dt @('Вільне місце на C:', $script:Mark.OK, "Вільно $(Format-Size $c.FreeSpace); для точок відновлення резервується 10 ГБ.") 'OK' }
    }

    if (Test-PendingReboot) { Add-Row $dt @('Очікує перезавантаження', $script:Mark.WARN, 'У системі є незавершені зміни. Бажано перезавантажити ПК перед застосуванням налаштувань.') 'WARN' }
    else { Add-Row $dt @('Очікує перезавантаження', $script:Mark.OK, 'Незавершених змін немає.') 'OK' }

    $up = (Get-Date) - $os.LastBootUpTime
    Add-Row $dt @('Час роботи', $script:Mark.INFO, ("{0} д {1} год {2} хв з останнього запуску" -f $up.Days, $up.Hours, $up.Minutes)) 'INFO'

    $prof = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -Name ProfilesDirectory -ErrorAction SilentlyContinue).ProfilesDirectory
    Add-Row $dt @('Каталог профілів', $script:Mark.INFO, "Зараз: $prof") 'INFO'

    try {
        $adm = Get-LocalUser | Where-Object { $_.SID -like '*-500' }
        $gst = Get-LocalUser | Where-Object { $_.SID -like '*-501' }
        $hardened = ($adm.Name -ne 'Administrator')
        if ($hardened) { Add-Row $dt @('Ознака застосованих політик', $script:Mark.INFO, "Вбудовані облікові записи перейменовано (адміністратор: «$($adm.Name)», гість: «$($gst.Name)») - схоже, збірку вже застосовували.") 'INFO' }
        else { Add-Row $dt @('Ознака застосованих політик', $script:Mark.INFO, 'Вбудовані облікові записи мають стандартні імена - збірку, найімовірніше, ще не застосовували.') 'INFO' }
    } catch {}

    if ($isAdmin) {
        try {
            $rp = Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object CreationTime | Select-Object -Last 1
            if ($rp) {
                $dtm = [Management.ManagementDateTimeConverter]::ToDateTime($rp.CreationTime)
                Add-Row $dt @('Остання точка відновлення', $script:Mark.INFO, "$($rp.Description) ($dtm)") 'INFO'
            } else { Add-Row $dt @('Остання точка відновлення', $script:Mark.WARN, 'Точок відновлення немає (скрипт створить її сам).') 'WARN' }
        } catch { Add-Row $dt @('Остання точка відновлення', $script:Mark.WARN, 'Захист системи вимкнено або недоступний (скрипт увімкне його сам).') 'WARN' }
    } else {
        Add-Row $dt @('Остання точка відновлення', $script:Mark.INFO, 'Для перегляду потрібні права адміністратора.') 'INFO'
    }
}

function Fill-Disks {
    $dt = $script:T.Disks; $dt.Clear()
    $types = @{ 0 = 'Невідомо'; 1 = 'Без кореня'; 2 = 'Змінний'; 3 = 'Локальний'; 4 = 'Мережевий'; 5 = 'Оптичний'; 6 = 'RAM-диск' }
    foreach ($l in (Get-CimInstance Win32_LogicalDisk | Sort-Object DeviceID)) {
        $role = ''; $st = 'INFO'
        if ($l.DeviceID -eq 'C:') { $role = 'Системний; сховище точок відновлення 10 ГБ'; $st = 'OK' }
        if ($l.DeviceID -eq 'D:') { $role = 'Профілі користувачів (D:\Користувачі)'; $st = 'OK' }
        $size = ''; $free = ''; $used = ''
        if ($l.Size) {
            $size = Format-Size $l.Size; $free = Format-Size $l.FreeSpace
            $pct = [math]::Round(100 * ($l.Size - $l.FreeSpace) / $l.Size)
            $used = "$pct %"
            if ($l.DeviceID -eq 'C:' -and $l.FreeSpace -lt 15GB) { $st = 'WARN' }
            if ($pct -ge 95) { $st = 'FAIL' } elseif ($pct -ge 85 -and $st -eq 'OK') { $st = 'WARN' }
        }
        Add-Row $dt @($l.DeviceID, $l.VolumeName, $types[[int]$l.DriveType], $l.FileSystem, $size, $free, $used, $role, $script:Mark[$st]) $st
    }
    if (-not ($dt.Rows | Where-Object { $_[0] -eq 'D:' })) {
        Add-Row $dt @('D:', '', '', '', '', '', '', 'Профілі користувачів (D:\Користувачі)', $script:Mark.WARN + ' диска немає') 'WARN'
    }

    $p = $script:T.Phys; $p.Clear()
    try {
        foreach ($pd in (Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId)) {
            $st = if ("$($pd.HealthStatus)" -eq 'Healthy') { 'OK' } else { 'WARN' }
            Add-Row $p @($pd.FriendlyName, "$($pd.MediaType)", "$($pd.BusType)", (Format-Size $pd.Size), "$($pd.HealthStatus)") $st
        }
    } catch {
        foreach ($dd in (Get-CimInstance Win32_DiskDrive)) { Add-Row $p @($dd.Model, '', $dd.InterfaceType, (Format-Size $dd.Size), $dd.Status) 'INFO' }
    }
}

# Опис збірок: відповідає меню Config.ps1
$script:Builds = @(
    @{ Label = 'Профіль A - ізольована станція (без мережі / закритий сегмент)'; Folder = 'Profile-A-Win10'; OS = 'Windows 10'; Menu = 'Головне меню → 1 → 1' },
    @{ Label = 'Профіль A - ізольована станція (без мережі / закритий сегмент)'; Folder = 'Profile-A-Win11'; OS = 'Windows 11'; Menu = 'Головне меню → 1 → 1' },
    @{ Label = 'Профіль B - ПК з інтернетом, екран завжди ввімкнено'; Folder = 'Profile-B-Win10'; OS = 'Windows 10'; Menu = 'Головне меню → 1 → 2' },
    @{ Label = 'Профіль B - ПК з інтернетом, екран завжди ввімкнено'; Folder = 'Profile-B-Win11'; OS = 'Windows 11'; Menu = 'Головне меню → 1 → 2' },
    @{ Label = 'Профіль C - ПК з інтернетом для користувачів'; Folder = 'Profile-C-Win10'; OS = 'Windows 10'; Menu = 'Головне меню → 1 → 3' },
    @{ Label = 'Профіль C - ПК з інтернетом для користувачів'; Folder = 'Profile-C-Win11'; OS = 'Windows 11'; Menu = 'Головне меню → 1 → 3' },
    @{ Label = 'Профіль B - оригінальна резервна копія'; Folder = 'Profile-B-Win10-Original-Backup'; OS = 'Windows 10'; Menu = 'не підключена до меню' }
)
$script:BuildNotes = @{
    'Profile-A-Win10' = 'Майже всі служби вимкнені (крім AppIDSvc). Базовий профіль безпеки з правками для коректної роботи.'
    'Profile-A-Win11' = 'Як Profile-A-Win10; у Windows 11 служба netprofm має тип Demand. Додатково пропонується прибрати Windows Terminal/PowerShell з меню Win+X.'
    'Profile-B-Win10' = 'Для ПК, що постійно показують інформацію: вимкнено скрінсейвер, сон і вимкнення екрана, не задано ліміт бездіяльності, вимкнено Copilot і «News and interests».'
    'Profile-B-Win11' = 'Як Win10-версія, для Windows 11.'
    'Profile-C-Win10' = 'Для користувачів: вимкнено Copilot і «News and interests»; Camera та блокування споживчих акаунтів Microsoft - «Не налаштовано» (потрібно для Teams).'
    'Profile-C-Win11' = 'Як Win10-версія, для Windows 11.'
    'Profile-B-Win10-Original-Backup' = 'Резервна «оригінальна» збірка. У меню скрипта не використовується; тільки у ній у текстовому вигляді знайдено імена Telegram/AnyDesk.'
}

function Fill-Configs {
    $dt = $script:T.Configs; $dt.Clear()
    $family = Get-WinFamily
    foreach ($b in $script:Builds) {
        $dir = Join-Path $script:Root "Configs\$($b.Folder)"
        $gpo = if (Test-Path $dir) { Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
        $when = ''; $m = ''; $u = ''; $a = ''; $g = ''
        if ($gpo) {
            try {
                $x = [xml](Get-Content (Join-Path $gpo.FullName 'Bkupinfo.xml') -Raw)
                $when = ([datetime]$x.BackupInst.BackupTime.InnerText).ToString('dd.MM.yyyy HH:mm')
            } catch {}
            $gp = Join-Path $gpo.FullName 'DomainSysvol\GPO'
            $fm = Join-Path $gp 'Machine\registry.pol'; $fu = Join-Path $gp 'User\registry.pol'
            $fa = Join-Path $gp 'Machine\microsoft\windows nt\Audit\audit.csv'; $fg = Join-Path $gp 'Machine\microsoft\windows nt\SecEdit\GptTmpl.inf'
            $m = if (Test-Path $fm) { Format-Size (Get-Item $fm).Length } else { 'немає' }
            $u = if (Test-Path $fu) { Format-Size (Get-Item $fu).Length } else { 'немає' }
            $a = if (Test-Path $fa) { 'є' } else { 'немає' }
            $g = if (Test-Path $fg) { 'є' } else { 'немає' }
        }
        $fit = if ($b.OS -eq $family) { 'Так' } else { 'Ні (інша ОС)' }
        $st = if (-not $gpo) { 'FAIL' } elseif ($b.OS -eq $family -and $b.Menu -notmatch 'не підключена') { 'OK' } else { 'INFO' }
        if ($b.Menu -match 'не підключена') { $fit = if ($b.OS -eq $family) { 'Так, але не в меню' } else { 'Ні' } }
        Add-Row $dt @($b.Label, $b.Folder, $b.OS, $b.Menu, $fit, $when, $m, $u, $a, $g) $st
    }
    Add-Row $dt @('Стандартні Security Settings (відкат)', 'LGPO-Default', 'Win10/11', 'Головне меню → 2',
        $(if (Test-Path (Join-Path $script:Root 'Configs\LGPO-Default\LGPO-Default-Security-Settings.inf')) { 'Так' } else { 'Файл відсутній' }), '', '', '', '', '.inf') 'INFO'
}

# Списки служб беремо з самого Config.ps1 (AST), щоб не дублювати дані
$script:ServiceProfiles = [ordered]@{
    'Профіль A, Windows 10'                     = 'ProfileAServices-Win10'
    'Профіль A, Windows 11'                     = 'ProfileAServices-Win11'
    'Профілі B і C (Win10/11)'     = 'ProfileBCServices-Win10-11'
    'Стандартні значення (відкат)'         = 'defaultServices'
}

function Get-ConfigServiceList([string]$functionName) {
    $path = Join-Path $script:Root 'Config.ps1'
    if (-not (Test-Path $path)) { return @() }
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok, [ref]$err)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $functionName }, $true)
    if (-not $fn) { return @() }
    $result = @()
    $tables = $fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
    foreach ($h in $tables) {
        $name = $null; $start = $null
        foreach ($kv in $h.KeyValuePairs) {
            $k = $kv.Item1.Extent.Text.Trim('"', "'"); $v = $kv.Item2.Extent.Text.Trim().Trim('"', "'")
            if ($k -eq 'Name') { $name = $v }
            if ($k -eq 'StartType') { $start = $v }
        }
        if ($name -and $start) { $result += [pscustomobject]@{ Name = $name; StartType = $start } }
    }
    return $result
}

function Convert-StartMode([string]$mode) {
    switch ($mode) { 'Auto' { 'AUTO' } 'Manual' { 'DEMAND' } 'Disabled' { 'DISABLED' } default { $mode.ToUpper() } }
}

function Fill-Services([string]$profileName) {
    $dt = $script:T.Services; $dt.Clear()
    $list = Get-ConfigServiceList $script:ServiceProfiles[$profileName]
    $cim = @{}
    foreach ($s in (Get-CimInstance Win32_Service)) { $cim[$s.Name] = $s }
    $same = 0; $diff = 0; $none = 0
    foreach ($svc in $list) {
        $target = $svc.StartType.ToUpper()
        if ($cim.ContainsKey($svc.Name)) {
            $cur = Convert-StartMode $cim[$svc.Name].StartMode
            if ($cur -eq $target) { $same++; Add-Row $dt @($svc.Name, $cim[$svc.Name].DisplayName, $cur, $target, ($script:Mark.OK + ' збігається')) 'OK' }
            else { $diff++; Add-Row $dt @($svc.Name, $cim[$svc.Name].DisplayName, $cur, $target, ($script:Mark.WARN + ' буде змінено')) 'WARN' }
        } else {
            $none++; Add-Row $dt @($svc.Name, '', '-', $target, 'служби немає в цій збірці Windows') 'INFO'
        }
    }
    $script:ServiceSummary = "Усього в списку: $($list.Count)   |   вже відповідають: $same   |   буде змінено: $diff   |   відсутні в системі: $none"
}

function Fill-Settings {
    $dt = $script:T.Settings; $dt.Clear()
    $regs = @(
        @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'CrashOnAuditFail'; V = 0 },
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; N = 'AutoAdminLogon'; V = 0 },
        @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'DisableIPSourceRouting'; V = 2 },
        @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'DeadGWDetectDefault'; V = 0 },
        @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'EnableICMPRedirect'; V = 0 },
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; N = 'NoDriveTypeAutoRun'; V = 255 },
        @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; N = 'NtfsDisable8dot3NameCreation'; V = 2 },
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'; N = 'ProfilesDirectory'; V = 'D:\Користувачі' }
    )
    foreach ($r in $regs) {
        $cur = (Get-ItemProperty -Path $r.P -Name $r.N -ErrorAction SilentlyContinue).($r.N)
        $curText = if ($null -eq $cur) { 'не задано' } else { "$cur" }
        $ok = ($null -ne $cur) -and ("$cur" -eq "$($r.V)")
        $st = if ($ok) { 'OK' } else { 'WARN' }
        $res = if ($ok) { $script:Mark.OK + ' збігається' } else { $script:Mark.WARN + ' буде змінено' }
        Add-Row $dt @('Реєстр', "$($r.N)  ($($r.P -replace '^HKLM:\\',''))", $curText, "$($r.V)", $res) $st
    }
    $logs = @(
        @{ N = 'Application'; V = 1073741824 }, @{ N = 'Security'; V = 2147483648 }, @{ N = 'System'; V = 1073741824 },
        @{ N = 'Microsoft-Windows-PowerShell/Operational'; V = 1073741824 },
        @{ N = 'Microsoft-Windows-TaskScheduler/Operational'; V = 157286400 }, @{ N = 'Windows PowerShell'; V = 1073741824 }
    )
    foreach ($l in $logs) {
        $cur = $null
        try { $cur = (Get-WinEvent -ListLog $l.N -ErrorAction Stop).MaximumSizeInBytes } catch {}
        if ($null -eq $cur) { Add-Row $dt @('Журнал подій', $l.N, 'недоступно (потрібні права адміністратора)', (Format-Size $l.V), 'не вдалося перевірити') 'INFO'; continue }
        $ok = ([int64]$cur -eq [int64]$l.V)
        Add-Row $dt @('Журнал подій', $l.N, (Format-Size $cur), (Format-Size $l.V), $(if ($ok) { $script:Mark.OK + ' збігається' } else { $script:Mark.WARN + ' буде змінено' })) $(if ($ok) { 'OK' } else { 'WARN' })
    }
}

function Fill-Files {
    $dt = $script:T.Files; $dt.Clear()
    foreach ($n in 'Config.ps1', 'GUI.ps1', 'LGPO.exe', 'AppLocker_Policy.xml', 'Run script.bat', 'README.md') {
        $p = Join-Path $script:Root $n
        if (Test-Path $p) {
            $i = Get-Item $p
            $h = (Get-FileHash $p -Algorithm SHA256).Hash.Substring(0, 16)
            Add-Row $dt @($n, (Format-Size $i.Length), $i.LastWriteTime.ToString('dd.MM.yyyy HH:mm'), $h) 'INFO'
        } else { Add-Row $dt @($n, '-', '-', 'файл відсутній') 'FAIL' }
    }
}

# ======================================================================= ІНТЕРФЕЙС

function New-Grid($dt, [hashtable]$weights = @{}) {
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Dock = 'Fill'
    $g.ReadOnly = $true
    $g.AllowUserToAddRows = $false; $g.AllowUserToDeleteRows = $false; $g.AllowUserToResizeRows = $false
    $g.RowHeadersVisible = $false
    $g.SelectionMode = 'FullRowSelect'; $g.MultiSelect = $false
    $g.BackgroundColor = [System.Drawing.Color]::White
    $g.BorderStyle = 'None'
    $g.GridColor = [System.Drawing.Color]::FromArgb(222, 226, 230)
    $g.EnableHeadersVisualStyles = $false
    $g.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(31, 56, 100)
    $g.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    $g.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $g.ColumnHeadersHeight = 32
    $g.ColumnHeadersHeightSizeMode = 'DisableResizing'
    $g.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(180, 200, 235)
    $g.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::Black
    $g.DefaultCellStyle.WrapMode = 'True'
    $g.AutoSizeRowsMode = 'AllCells'
    $g.AutoSizeColumnsMode = 'Fill'
    # Колонки створюємо вручну: автогенерація не спрацьовує, поки елемент не показано
    $g.AutoGenerateColumns = $false
    foreach ($col in $dt.Columns) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name = $col.ColumnName; $c.HeaderText = $col.ColumnName; $c.DataPropertyName = $col.ColumnName
        $c.SortMode = 'NotSortable'
        if ($col.ColumnName -eq '_st') { $c.Visible = $false }
        elseif ($weights.ContainsKey($col.ColumnName)) { $c.FillWeight = $weights[$col.ColumnName] }
        [void]$g.Columns.Add($c)
    }
    $g.DataSource = $dt
    $g.add_CellFormatting({
        param($s, $e)
        if ($e.RowIndex -ge 0) {
            $st = [string]$s.Rows[$e.RowIndex].Cells['_st'].Value
            if ($script:Colors.ContainsKey($st)) { $e.CellStyle.BackColor = $script:Colors[$st] }
        }
    })
    return $g
}

function New-Label([string]$text, [string]$style = 'Regular', [float]$size = 9.5, $color = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $size, [System.Drawing.FontStyle]$style)
    if ($color) { $l.ForeColor = $color }
    return $l
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GroupPolicyAutomation - панель адміністратора'
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.MinimumSize = New-Object System.Drawing.Size(900, 600)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

# --- шапка
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = 92; $header.BackColor = [System.Drawing.Color]::FromArgb(31, 56, 100)
$title = New-Label 'GroupPolicyAutomation' 'Bold' 18 ([System.Drawing.Color]::White); $title.Location = New-Object System.Drawing.Point(16, 10)
$sub = New-Label 'Автоматизація захисту Windows 10/11 - огляд системи та профілів' 'Regular' 9.5 ([System.Drawing.Color]::FromArgb(200, 214, 238))
$sub.Location = New-Object System.Drawing.Point(18, 54)
$badgeAdmin = New-Object System.Windows.Forms.Label
$badgeOS = New-Object System.Windows.Forms.Label
foreach ($b in $badgeAdmin, $badgeOS) {
    $b.AutoSize = $false; $b.Size = New-Object System.Drawing.Size(210, 30); $b.TextAlign = 'MiddleCenter'
    $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5); $b.ForeColor = [System.Drawing.Color]::White
    $b.Anchor = 'Top, Right'
}
$badgePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$badgePanel.Dock = 'Right'; $badgePanel.Width = 450; $badgePanel.Padding = New-Object System.Windows.Forms.Padding(0, 26, 12, 0)
$badgePanel.BackColor = [System.Drawing.Color]::Transparent
$badgePanel.Controls.AddRange(@($badgeAdmin, $badgeOS))
$header.Controls.AddRange(@($title, $sub, $badgePanel))

# --- нижня панель кнопок
$footer = New-Object System.Windows.Forms.FlowLayoutPanel
$footer.Dock = 'Bottom'; $footer.Height = 64; $footer.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 8)
$footer.BackColor = [System.Drawing.Color]::FromArgb(236, 239, 244)
function New-Button([string]$text, [int]$w = 200) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.AutoSize = $true; $b.AutoSizeMode = 'GrowAndShrink'; $b.MinimumSize = New-Object System.Drawing.Size($w, 38)
    $b.Padding = New-Object System.Windows.Forms.Padding(10, 2, 10, 2); $b.FlatStyle = 'System'
    return $b
}
$btnRefresh = New-Button 'Оновити' 120
$btnRun = New-Button 'Запустити Config.ps1' 190
$btnElevate = New-Button 'Перезапустити від адміністратора' 260
$btnFolder = New-Button 'Відкрити папку проєкту' 190
$btnReport = New-Button 'Зберегти звіт' 140
$footer.Controls.AddRange(@($btnRefresh, $btnRun, $btnElevate, $btnFolder, $btnReport))

# --- вкладки
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'; $tabs.Padding = New-Object System.Drawing.Point(14, 6)
function New-Tab([string]$text) {
    $t = New-Object System.Windows.Forms.TabPage
    $t.Text = $text; $t.BackColor = [System.Drawing.Color]::White
    return $t
}

# Огляд
$tabOverview = New-Tab 'Огляд'
$gOverview = New-Grid $script:T.Overview @{ 'Перевірка' = 26; 'Результат' = 14; 'Деталі' = 70 }
$lblOverview = New-Label '' 'Bold' 10; $lblOverview.Dock = 'Top'; $lblOverview.Padding = New-Object System.Windows.Forms.Padding(8, 8, 0, 8)
$tabOverview.Controls.Add($gOverview); $tabOverview.Controls.Add($lblOverview)

# Диски
$tabDisks = New-Tab 'Диски'
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'; $split.Orientation = 'Horizontal'; $split.BackColor = [System.Drawing.Color]::White
$gDisks = New-Grid $script:T.Disks @{ 'Диск' = 7; 'Назва' = 14; 'Тип' = 10; 'ФС' = 7; 'Обсяг' = 10; 'Вільно' = 10; 'Заповнено' = 10; 'Роль у скрипті' = 30; 'Стан' = 14 }
$gPhys = New-Grid $script:T.Phys @{ 'Модель' = 40; 'Тип носія' = 14; 'Шина' = 12; 'Обсяг' = 14; 'Стан здоров''я' = 20 }
$l1 = New-Label 'Логічні диски (розділи)' 'Bold' 10; $l1.Dock = 'Top'; $l1.Padding = New-Object System.Windows.Forms.Padding(6, 6, 0, 6)
$l2 = New-Label 'Фізичні накопичувачі' 'Bold' 10; $l2.Dock = 'Top'; $l2.Padding = New-Object System.Windows.Forms.Padding(6, 6, 0, 6)
$split.Panel1.Controls.Add($gDisks); $split.Panel1.Controls.Add($l1)
$split.Panel2.Controls.Add($gPhys); $split.Panel2.Controls.Add($l2)
$tabDisks.Controls.Add($split)

# Конфігурації
$tabCfg = New-Tab 'Конфігурації'
$gCfg = New-Grid $script:T.Configs @{ 'Збірка' = 21; 'Папка Configs' = 25; 'ОС' = 10; 'Пункт меню' = 14; 'Підходить цьому ПК' = 12; 'Дата копії' = 11; 'Machine' = 9; 'User' = 6; 'audit.csv' = 7; 'GptTmpl.inf' = 9 }
$noteBox = New-Object System.Windows.Forms.TextBox
$noteBox.Dock = 'Bottom'; $noteBox.Multiline = $true; $noteBox.ReadOnly = $true; $noteBox.Height = 96
$noteBox.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250); $noteBox.BorderStyle = 'None'
$noteBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$noteBox.Text = 'Оберіть рядок, щоб побачити опис збірки.'
$gCfg.add_SelectionChanged({
    if ($gCfg.CurrentRow) {
        $f = [string]$gCfg.CurrentRow.Cells['Папка Configs'].Value
        if ($script:BuildNotes.ContainsKey($f)) { $noteBox.Text = "$f`r`n" + $script:BuildNotes[$f] }
        elseif ($f -eq 'LGPO-Default') { $noteBox.Text = "LGPO-Default`r`nСтандартні Security Settings для відкату (secedit /configure). Використовується пунктом 2 головного меню." }
    }
})
$tabCfg.Controls.Add($gCfg); $tabCfg.Controls.Add($noteBox)

# Служби
$tabSvc = New-Tab 'Служби'
$gSvc = New-Grid $script:T.Services @{ 'Служба' = 18; 'Назва' = 38; 'Поточний' = 12; 'Цільовий' = 12; 'Результат' = 22 }
$topSvc = New-Object System.Windows.Forms.Panel; $topSvc.Dock = 'Top'; $topSvc.Height = 62
$lblPick = New-Label 'Набір служб:' 'Regular' 9.5; $lblPick.Location = New-Object System.Drawing.Point(8, 10)
$cmbSvc = New-Object System.Windows.Forms.ComboBox
$cmbSvc.DropDownStyle = 'DropDownList'; $cmbSvc.Width = 360; $cmbSvc.Location = New-Object System.Drawing.Point(140, 6)
foreach ($k in $script:ServiceProfiles.Keys) { [void]$cmbSvc.Items.Add($k) }
$lblSvcSum = New-Label '' 'Bold' 9.5; $lblSvcSum.Location = New-Object System.Drawing.Point(8, 36)
$topSvc.Controls.AddRange(@($lblPick, $cmbSvc, $lblSvcSum))
$tabSvc.Controls.Add($gSvc); $tabSvc.Controls.Add($topSvc)

# Реєстр і журнали
$tabSet = New-Tab 'Реєстр і журнали'
$gSet = New-Grid $script:T.Settings @{ 'Категорія' = 12; 'Параметр' = 44; 'Поточне' = 16; 'Цільове' = 16; 'Результат' = 16 }
$tabSet.Controls.Add($gSet)

# Про проєкт
$tabAbout = New-Tab 'Про проєкт'
$gFiles = New-Grid $script:T.Files @{ 'Файл' = 30; 'Розмір' = 12; 'Змінено' = 20; 'SHA-256 (початок)' = 38 }
$aboutBox = New-Object System.Windows.Forms.TextBox
$aboutBox.Dock = 'Top'; $aboutBox.Multiline = $true; $aboutBox.ReadOnly = $true; $aboutBox.Height = 230
$aboutBox.BackColor = [System.Drawing.Color]::White; $aboutBox.BorderStyle = 'None'
$aboutBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$aboutBox.Text = (@(
    'GroupPolicyAutomation',
    'Автоматизоване застосування захисних налаштувань Windows 10/11 за трьома профілями: політики безпеки (LGPO), служби, реєстр, журнали подій, AppLocker.',
    '',
    'Ця панель лише показує стан і нічого не змінює. Налаштування застосовуються кнопкою «Запустити Config.ps1» - відкриється консольне меню, де кожен крок потрібно підтвердити.',
    'Перед застосуванням скрипт створює точку відновлення. Перевіряйте збірки на тестовій машині або ВМ.',
    '',
    "Каталог проєкту: $($script:Root)"
) -join "`r`n")
$tabAbout.Controls.Add($gFiles); $tabAbout.Controls.Add($aboutBox)

$tabs.TabPages.AddRange(@($tabOverview, $tabDisks, $tabCfg, $tabSvc, $tabSet, $tabAbout))
$form.Controls.Add($tabs); $form.Controls.Add($footer); $form.Controls.Add($header)
$header.BringToFront(); $footer.BringToFront(); $tabs.BringToFront()

# ======================================================================= ЛОГІКА

function Update-Badges {
    $isAdmin = Test-IsAdmin
    $badgeAdmin.Text = if ($isAdmin) { [string][char]0x2714 + '  Адміністратор' } else { [string][char]0x2716 + '  Не адміністратор' }
    $badgeAdmin.BackColor = if ($isAdmin) { [System.Drawing.Color]::FromArgb(40, 140, 80) } else { [System.Drawing.Color]::FromArgb(200, 50, 60) }
    $fam = Get-WinFamily
    $badgeOS.Text = if ($fam -eq 'Unknown') { $script:Mark.FAIL + '  ОС не підтримується' } else { "$fam" }
    $badgeOS.BackColor = if ($fam -eq 'Unknown') { [System.Drawing.Color]::FromArgb(200, 50, 60) } else { [System.Drawing.Color]::FromArgb(47, 84, 150) }
    $btnElevate.Visible = -not $isAdmin
    $btnRun.Enabled = ($fam -ne 'Unknown')
}

function Update-All {
    $form.Cursor = 'WaitCursor'
    try {
        Update-Badges
        Fill-Overview
        $ok = @($script:T.Overview.Rows | Where-Object { $_['_st'] -eq 'OK' }).Count
        $wn = @($script:T.Overview.Rows | Where-Object { $_['_st'] -eq 'WARN' }).Count
        $fl = @($script:T.Overview.Rows | Where-Object { $_['_st'] -eq 'FAIL' }).Count
        $lblOverview.Text = "Готовність до налаштування:   $($script:Mark.OK): $ok     $($script:Mark.WARN): $wn     $($script:Mark.FAIL): $fl"
        $lblOverview.ForeColor = if ($fl -gt 0) { [System.Drawing.Color]::FromArgb(176, 32, 44) } elseif ($wn -gt 0) { [System.Drawing.Color]::FromArgb(150, 100, 0) } else { [System.Drawing.Color]::FromArgb(30, 120, 60) }
        Fill-Disks; Fill-Configs; Fill-Settings; Fill-Files
        if ($cmbSvc.SelectedIndex -lt 0) {
            $fam = Get-WinFamily
            $cmbSvc.SelectedIndex = if ($fam -eq 'Windows 11') { 1 } else { 0 }   # ініціює Fill-Services
        } else { Fill-Services $cmbSvc.SelectedItem; $lblSvcSum.Text = $script:ServiceSummary }
    } finally { $form.Cursor = 'Default' }
    # Без виділеного рядка, щоб було видно кольори статусів
    foreach ($g in $gOverview, $gDisks, $gPhys, $gSvc, $gSet, $gFiles) { $g.ClearSelection() }
}

$cmbSvc.add_SelectedIndexChanged({
    if ($cmbSvc.SelectedItem) {
        $form.Cursor = 'WaitCursor'
        try { Fill-Services $cmbSvc.SelectedItem; $lblSvcSum.Text = $script:ServiceSummary } finally { $form.Cursor = 'Default' }
    }
})
$btnRefresh.add_Click({ Update-All })
$btnFolder.add_Click({ Start-Process explorer.exe $script:Root })
$btnRun.add_Click({
    $msg = "Відкриється консольне меню Config.ps1 (з правами адміністратора).`r`nЗміни застосовуються лише після ваших підтверджень у ньому, перед цим створюється точка відновлення.`r`n`r`nПродовжити?"
    if ([System.Windows.Forms.MessageBox]::Show($msg, 'Запуск Config.ps1', 'YesNo', 'Question') -eq 'Yes') {
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($script:Root)\Config.ps1`""
        } catch { [System.Windows.Forms.MessageBox]::Show("Не вдалося запустити: $($_.Exception.Message)", 'Помилка', 'OK', 'Error') | Out-Null }
    }
})
$btnElevate.add_Click({
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$($script:Root)\GUI.ps1`""
        $form.Close()
    } catch { [System.Windows.Forms.MessageBox]::Show("Не вдалося перезапустити: $($_.Exception.Message)", 'Помилка', 'OK', 'Error') | Out-Null }
})
$btnReport.add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'Текстовий файл (*.txt)|*.txt'
    $dlg.FileName = "GroupPolicyAutomation-звіт-$($env:COMPUTERNAME)-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
    if ($dlg.ShowDialog() -eq 'OK') {
        $out = New-Object System.Collections.Generic.List[string]
        $out.Add("GroupPolicyAutomation - звіт про стан системи"); $out.Add("ПК: $env:COMPUTERNAME   Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"); $out.Add('')
        $names = @{ Overview = 'ОГЛЯД'; Disks = 'ЛОГІЧНІ ДИСКИ'; Phys = 'ФІЗИЧНІ НАКОПИЧУВАЧІ'; Configs = 'КОНФІГУРАЦІЇ'; Services = "СЛУЖБИ ($($cmbSvc.SelectedItem))"; Settings = 'РЕЄСТР І ЖУРНАЛИ'; Files = 'ФАЙЛИ ПРОЄКТУ' }
        foreach ($k in $script:T.Keys) {
            $dt = $script:T[$k]; $out.Add("=== $($names[$k]) ===")
            $cols = @($dt.Columns | Where-Object { $_.ColumnName -ne '_st' } | ForEach-Object { $_.ColumnName })
            $out.Add(($cols -join ' | '))
            foreach ($r in $dt.Rows) { $out.Add((($cols | ForEach-Object { "$($r[$_])" }) -join ' | ')) }
            $out.Add('')
        }
        [IO.File]::WriteAllLines($dlg.FileName, $out, (New-Object System.Text.UTF8Encoding($true)))
        [System.Windows.Forms.MessageBox]::Show("Звіт збережено:`r`n$($dlg.FileName)", 'Готово', 'OK', 'Information') | Out-Null
    }
})
$form.add_Shown({
    $split.SplitterDistance = [int]($split.Height * 0.6)
    foreach ($g in $gOverview, $gDisks, $gPhys, $gSvc, $gSet, $gFiles) { $g.ClearSelection() }
})

Update-All

if ($Screenshot) {
    New-Item -ItemType Directory -Force -Path $Screenshot | Out-Null
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    $split.SplitterDistance = [int]($split.Height * 0.6)
    foreach ($g in $gOverview, $gDisks, $gPhys, $gSvc, $gSet, $gFiles) { $g.ClearSelection() }
    $i = 0
    foreach ($tp in $tabs.TabPages) {
        $tabs.SelectedTab = $tp
        if ($tp -eq $tabCfg -and $gCfg.Rows.Count -gt 0) { $gCfg.CurrentCell = $gCfg.Rows[0].Cells[0] }
        [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300; [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save((Join-Path $Screenshot ("tab{0}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $i++
    }
    $form.Close()
    return
}

[void]$form.ShowDialog()

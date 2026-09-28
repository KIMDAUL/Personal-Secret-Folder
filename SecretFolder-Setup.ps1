<#
    SECRET FOLDER - 설치 관리자 (설치 / 삭제)
    ------------------------------------------------------------
    Windows에 기본 내장된 PowerShell로 동작하므로, 처음 쓰는 사람도
    별도 프로그램 없이 이 창 하나로 설치할 수 있습니다.

    - [원클릭 설치] : AutoHotkey + VeraCrypt를 자동으로 받아 설치하고,
                      지정한 크기/비밀번호로 암호화 금고를 만든 뒤
                      바탕화면 secret/hide 기능을 켭니다.
    - [SECRET 폴더 삭제] : 금고가 비어 있을 때만 삭제합니다.

    사용법:  SECRET-Folder-설치.bat 을 더블클릭 (또는 이 파일을 PowerShell로 실행)
    자체 점검:  powershell -ExecutionPolicy Bypass -File SecretFolder-Setup.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# 다운로드 대상 (winget 실패 시 직접 내려받는 공식 주소)
$script:AhkVer   = '2.0.26'
$script:AhkUrl   = "https://github.com/AutoHotkey/AutoHotkey/releases/download/v$($script:AhkVer)/AutoHotkey_$($script:AhkVer)_setup.exe"
$script:VcVer    = '1.26.29'
$script:VcUrl    = "https://launchpad.net/veracrypt/trunk/$($script:VcVer)/+download/VeraCrypt_Setup_x64_$($script:VcVer).msi"

# ------------------------------------------------------------------
# 설정 / 경로
# ------------------------------------------------------------------
function Get-Config {
    param([string]$InstallRoot)
    if (-not $InstallRoot) { $InstallRoot = Join-Path $HOME '.secretvault' }
    [pscustomobject]@{
        InstallRoot   = $InstallRoot
        VaultPath     = Join-Path $InstallRoot 'vault.hc'
        ScriptPath    = Join-Path $InstallRoot 'SecretFolder.ahk'
        StatePath     = Join-Path $InstallRoot 'state.ini'
        SourceScript  = Join-Path $script:Root 'src\SecretFolder.ahk'
        Marker        = '.secret_marker'
        Desktop       = [Environment]::GetFolderPath('Desktop')
        Startup       = [Environment]::GetFolderPath('Startup')
        StartupLnk    = Join-Path ([Environment]::GetFolderPath('Startup')) 'SecretFolder.lnk'
        DesktopLnk    = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SECRET.lnk'
    }
}

# ------------------------------------------------------------------
# 프로그램 위치 찾기
# ------------------------------------------------------------------
function Find-AutoHotkey {
    $c = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey32.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey32.exe')
    )
    foreach ($p in $c) { if (Test-Path $p) { return $p } }
    return $null
}
function Find-VeraCryptFormat {
    $c = @(
        (Join-Path $env:ProgramFiles 'VeraCrypt\VeraCrypt Format.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'VeraCrypt\VeraCrypt Format.exe')
    )
    foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}
function Find-VeraCrypt {
    $c = @(
        (Join-Path $env:ProgramFiles 'VeraCrypt\VeraCrypt.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'VeraCrypt\VeraCrypt.exe')
    )
    foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

# ------------------------------------------------------------------
# 의존 프로그램 설치 (winget 우선 → 직접 다운로드 폴백)
#   $Log = { param($msg) ... }  진행 상황 콜백
# ------------------------------------------------------------------
function Install-Dependencies {
    param([scriptblock]$Log = { param($m) Write-Host $m })

    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if (-not (Find-AutoHotkey)) {
        & $Log 'AutoHotkey 설치 중...'
        $ok = $false
        if ($winget) {
            try {
                Start-Process winget -Wait -ArgumentList @('install','-e','--id','AutoHotkey.AutoHotkey','--source','winget','--scope','user','--silent','--accept-package-agreements','--accept-source-agreements')
                $ok = [bool](Find-AutoHotkey)
            } catch { $ok = $false }
        }
        if (-not $ok) {
            & $Log '  winget 실패 → 공식 사이트에서 직접 내려받는 중...'
            $tmp = Join-Path $env:TEMP "ahk_setup.exe"
            (New-Object Net.WebClient).DownloadFile($script:AhkUrl, $tmp)
            Start-Process $tmp -Wait -ArgumentList '/silent'
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
        if (-not (Find-AutoHotkey)) { throw 'AutoHotkey 설치에 실패했습니다.' }
        & $Log '  AutoHotkey 설치 완료.'
    } else {
        & $Log 'AutoHotkey 이미 설치됨.'
    }

    if (-not (Find-VeraCrypt)) {
        & $Log 'VeraCrypt 설치 중... (관리자 권한 창이 뜰 수 있습니다)'
        $ok = $false
        if ($winget) {
            try {
                Start-Process winget -Wait -ArgumentList @('install','-e','--id','IDRIX.VeraCrypt','--source','winget','--silent','--accept-package-agreements','--accept-source-agreements')
                $ok = [bool](Find-VeraCrypt)
            } catch { $ok = $false }
        }
        if (-not $ok) {
            & $Log '  winget 실패 → 공식 사이트에서 직접 내려받는 중...'
            $tmp = Join-Path $env:TEMP "veracrypt_setup.msi"
            (New-Object Net.WebClient).DownloadFile($script:VcUrl, $tmp)
            Start-Process msiexec.exe -Wait -Verb RunAs -ArgumentList @('/i', "`"$tmp`"", '/qn', '/norestart')
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
        if (-not (Find-VeraCrypt)) { throw 'VeraCrypt 설치에 실패했습니다.' }
        & $Log '  VeraCrypt 설치 완료.'
    } else {
        & $Log 'VeraCrypt 이미 설치됨.'
    }
}

# ------------------------------------------------------------------
# 빈 드라이브 문자 하나
# ------------------------------------------------------------------
function Get-FreeDriveLetter {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($L in [char[]]('S','R','Q','P','O','N','M','L','K','J','I','H','T','U','V','W','X','Y','Z')) {
        if ($used -notcontains "$L") { return "$L" }
    }
    return $null
}

# ------------------------------------------------------------------
# 암호화 금고 만들기 + 표시용 마커 파일 기록
# ------------------------------------------------------------------
function New-Vault {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [int]$SizeGB,
        [Parameter(Mandatory)] [string]$Password,
        [scriptblock]$Log = { param($m) Write-Host $m }
    )
    $fmt = Find-VeraCryptFormat
    $vc  = Find-VeraCrypt
    if (-not $fmt -or -not $vc) { throw 'VeraCrypt를 찾을 수 없습니다.' }

    New-Item -ItemType Directory -Force $Config.InstallRoot | Out-Null
    if (Test-Path $Config.VaultPath) { throw '이미 금고 파일이 있습니다.' }

    & $Log "금고 생성 중... ($SizeGB GB, 잠시 걸립니다)"
    $p = Start-Process $fmt -Wait -PassThru -ArgumentList @(
        '/create', "`"$($Config.VaultPath)`"", '/size', "${SizeGB}G",
        '/password', "`"$Password`"", '/encryption', 'AES', '/hash', 'sha512',
        '/filesystem', 'NTFS', '/silent')
    if ($p.ExitCode -ne 0 -or -not (Test-Path $Config.VaultPath)) {
        throw "금고 생성 실패 (코드 $($p.ExitCode))."
    }

    & $Log '마커 기록 중...'
    $L = Get-FreeDriveLetter
    if (-not $L) { throw '사용 가능한 드라이브 문자가 없습니다.' }
    $m = Start-Process $vc -Wait -PassThru -ArgumentList @(
        '/v', "`"$($Config.VaultPath)`"", '/l', $L, '/hash', 'sha512',
        '/p', "`"$Password`"", '/q', '/s', '/h', 'n')
    if ($m.ExitCode -ne 0 -or -not (Test-Path "${L}:\")) { throw '금고 마운트 실패.' }
    try {
        $marker = "${L}:\$($Config.Marker)"
        Set-Content -LiteralPath $marker -Value 'SECRET vault marker - do not delete' -Encoding ascii
        (Get-Item -LiteralPath $marker -Force).Attributes = 'Hidden,System,Archive'
    } finally {
        Start-Process $vc -Wait -ArgumentList @('/u', $L, '/q', '/s') | Out-Null
    }
    & $Log '금고 준비 완료.'
}

# ------------------------------------------------------------------
# 전체 설치
# ------------------------------------------------------------------
function Install-SecretFolder {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [int]$SizeGB,
        [Parameter(Mandatory)] [string]$Password,
        [scriptblock]$Log = { param($m) Write-Host $m }
    )
    if (-not (Test-Path $Config.SourceScript)) { throw "원본 스크립트를 찾을 수 없습니다: $($Config.SourceScript)" }

    Install-Dependencies -Log $Log
    New-Vault -Config $Config -SizeGB $SizeGB -Password $Password -Log $Log

    & $Log '스크립트 배치 중...'
    Copy-Item $Config.SourceScript $Config.ScriptPath -Force

    # 설치 폴더 숨김
    attrib +h +s "$($Config.InstallRoot)" | Out-Null

    & $Log '시작프로그램 등록 중...'
    $ahk = Find-AutoHotkey
    $ws  = New-Object -ComObject WScript.Shell
    $s   = $ws.CreateShortcut($Config.StartupLnk)
    $s.TargetPath       = $ahk
    $s.Arguments        = "`"$($Config.ScriptPath)`" /boot"
    $s.WorkingDirectory = $Config.InstallRoot
    $s.Save()

    & $Log '스크립트 실행 중...'
    Start-Process $ahk -ArgumentList "`"$($Config.ScriptPath)`""
    & $Log '설치 완료! 바탕화면에서 secret 을 입력해 보세요.'
}

# ------------------------------------------------------------------
# 금고 안의 사용자 파일 수 (마커/시스템 폴더 제외)
#   반환: [int] 사용자 파일/폴더 수.  마운트 못하면 예외.
# ------------------------------------------------------------------
function Get-VaultUserItemCount {
    param([Parameter(Mandatory)][string]$DriveLetter, [Parameter(Mandatory)]$Config)
    $root = "${DriveLetter}:\"
    $ignore = @($Config.Marker, 'System Volume Information', '$RECYCLE.BIN')
    $items = Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue |
             Where-Object { $ignore -notcontains $_.Name }
    return @($items).Count
}

# ------------------------------------------------------------------
# 삭제 흐름
#   $AskPassword = { param($prompt) return 'plaintext' or $null }
#   $Confirm     = { param($msg) return $true/$false }
#   $Info        = { param($msg) ... }
#   반환: 'deleted' / 'notempty' / 'cancelled' / 'notinstalled' / 'wrongpw' / 'error:...'
# ------------------------------------------------------------------
function Remove-SecretFolder {
    param(
        [Parameter(Mandatory)] $Config,
        [scriptblock]$AskPassword = { param($p) $null },
        [scriptblock]$Confirm     = { param($m) $false },
        [scriptblock]$Info        = { param($m) Write-Host $m }
    )
    if (-not (Test-Path $Config.VaultPath)) {
        & $Info 'SECRET 폴더가 설치되어 있지 않습니다.'
        return 'notinstalled'
    }

    $vc = Find-VeraCrypt
    if (-not $vc) { & $Info 'VeraCrypt를 찾을 수 없습니다.'; return 'error:noveracrypt' }

    # 현재 마운트된 드라이브 찾기
    $mounted = $null
    foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
        if (Test-Path (Join-Path "$($d.Name):\" $Config.Marker)) { $mounted = "$($d.Name)"; break }
    }

    $weMounted = $false
    if (-not $mounted) {
        $pw = & $AskPassword '삭제하려면 비밀번호를 입력하세요.'
        if (-not $pw) { return 'cancelled' }
        $L = Get-FreeDriveLetter
        if (-not $L) { & $Info '사용 가능한 드라이브 문자가 없습니다.'; return 'error:noletter' }
        $m = Start-Process $vc -Wait -PassThru -ArgumentList @(
            '/v', "`"$($Config.VaultPath)`"", '/l', $L, '/hash', 'sha512',
            '/p', "`"$pw`"", '/q', '/s', '/h', 'n')
        if ($m.ExitCode -ne 0 -or -not (Test-Path "${L}:\")) {
            & $Info '비밀번호가 올바르지 않습니다.'
            return 'wrongpw'
        }
        $mounted = $L
        $weMounted = $true
    }

    try {
        $count = Get-VaultUserItemCount -DriveLetter $mounted -Config $Config
    } catch {
        if ($weMounted) { Start-Process $vc -Wait -ArgumentList @('/u', $mounted, '/q', '/s') | Out-Null }
        & $Info "폴더 내용을 확인하지 못했습니다: $_"
        return 'error:read'
    }

    if ($count -gt 0) {
        if ($weMounted) { Start-Process $vc -Wait -ArgumentList @('/u', $mounted, '/q', '/s') | Out-Null }
        & $Info 'SECRET폴더에 파일이 남아있습니다. 폴더를 비우고 다시 시도해주세요.'
        return 'notempty'
    }

    # 비어 있음 → 최종 확인
    if (-not (& $Confirm '정말로 SECRET폴더를 삭제하시겠습니까?')) {
        if ($weMounted) { Start-Process $vc -Wait -ArgumentList @('/u', $mounted, '/q', '/s') | Out-Null }
        return 'cancelled'
    }

    # 마운트 해제 후 전체 삭제
    Start-Process $vc -Wait -ArgumentList @('/u', $mounted, '/f', '/q', '/s') | Out-Null
    Start-Sleep -Milliseconds 500

    # 실행 중인 스크립트 종료
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='AutoHotkey32.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*SecretFolder.ahk*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Remove-Item $Config.StartupLnk -Force -ErrorAction SilentlyContinue
    Remove-Item $Config.DesktopLnk -Force -ErrorAction SilentlyContinue
    if (Test-Path $Config.InstallRoot) {
        attrib -h -s "$($Config.InstallRoot)" | Out-Null
        Remove-Item $Config.InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    & $Info 'SECRET 폴더를 삭제했습니다.'
    return 'deleted'
}

# ==================================================================
# GUI
# ==================================================================
function Show-MainForm {
    param([switch]$BuildOnly)   # BuildOnly: 창을 띄우지 않고 구성만 (자체 점검용)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $cfg = Get-Config
    $installed = Test-Path $cfg.VaultPath

    $font = New-Object System.Drawing.Font('Malgun Gothic', 9)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'SECRET FOLDER'
    $form.Size = New-Object System.Drawing.Size(440, 470)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.Font = $font

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'SECRET FOLDER'
    $title.Font = New-Object System.Drawing.Font('Malgun Gothic', 15, [System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(20, 15)
    $title.AutoSize = $true
    $form.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = '바탕화면에서 secret 입력 → 비밀번호 → 열림 / hide 입력 → 잠김'
    $sub.Location = New-Object System.Drawing.Point(22, 48)
    $sub.AutoSize = $true
    $sub.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($sub)

    # ---- 설치 그룹 ----
    $gbI = New-Object System.Windows.Forms.GroupBox
    $gbI.Text = '설치'
    $gbI.Location = New-Object System.Drawing.Point(20, 80)
    $gbI.Size = New-Object System.Drawing.Size(390, 175)
    $form.Controls.Add($gbI)

    $lSize = New-Object System.Windows.Forms.Label
    $lSize.Text = '폴더 크기 (GB):'
    $lSize.Location = New-Object System.Drawing.Point(18, 30)
    $lSize.AutoSize = $true
    $gbI.Controls.Add($lSize)

    $numSize = New-Object System.Windows.Forms.NumericUpDown
    $numSize.Minimum = 1
    $numSize.Maximum = 4096
    $numSize.Value = 10
    $numSize.Location = New-Object System.Drawing.Point(150, 27)
    $numSize.Size = New-Object System.Drawing.Size(80, 25)
    $gbI.Controls.Add($numSize)

    $lPw = New-Object System.Windows.Forms.Label
    $lPw.Text = '초기 비밀번호:'
    $lPw.Location = New-Object System.Drawing.Point(18, 66)
    $lPw.AutoSize = $true
    $gbI.Controls.Add($lPw)

    $txtPw = New-Object System.Windows.Forms.TextBox
    $txtPw.UseSystemPasswordChar = $true
    $txtPw.Location = New-Object System.Drawing.Point(150, 63)
    $txtPw.Size = New-Object System.Drawing.Size(220, 25)
    $gbI.Controls.Add($txtPw)

    $lPw2 = New-Object System.Windows.Forms.Label
    $lPw2.Text = '비밀번호 확인:'
    $lPw2.Location = New-Object System.Drawing.Point(18, 100)
    $lPw2.AutoSize = $true
    $gbI.Controls.Add($lPw2)

    $txtPw2 = New-Object System.Windows.Forms.TextBox
    $txtPw2.UseSystemPasswordChar = $true
    $txtPw2.Location = New-Object System.Drawing.Point(150, 97)
    $txtPw2.Size = New-Object System.Drawing.Size(220, 25)
    $gbI.Controls.Add($txtPw2)

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = '원클릭 설치'
    $btnInstall.Location = New-Object System.Drawing.Point(150, 133)
    $btnInstall.Size = New-Object System.Drawing.Size(220, 32)
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
    $btnInstall.ForeColor = [System.Drawing.Color]::White
    $btnInstall.FlatStyle = 'Flat'
    $gbI.Controls.Add($btnInstall)

    # ---- 삭제 그룹 ----
    $gbD = New-Object System.Windows.Forms.GroupBox
    $gbD.Text = '삭제'
    $gbD.Location = New-Object System.Drawing.Point(20, 265)
    $gbD.Size = New-Object System.Drawing.Size(390, 70)
    $form.Controls.Add($gbD)

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = 'SECRET 폴더 삭제'
    $btnDelete.Location = New-Object System.Drawing.Point(18, 25)
    $btnDelete.Size = New-Object System.Drawing.Size(352, 32)
    $btnDelete.BackColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $btnDelete.FlatStyle = 'Flat'
    $gbD.Controls.Add($btnDelete)

    # ---- 로그 ----
    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline = $true
    $log.ReadOnly = $true
    $log.ScrollBars = 'Vertical'
    $log.Location = New-Object System.Drawing.Point(20, 345)
    $log.Size = New-Object System.Drawing.Size(390, 75)
    $log.BackColor = [System.Drawing.Color]::White
    $form.Controls.Add($log)

    $writeLog = {
        param($m)
        $log.AppendText(('{0}  {1}{2}' -f (Get-Date -Format 'HH:mm:ss'), $m, "`r`n"))
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $refreshState = {
        $isInst = Test-Path $cfg.VaultPath
        $btnInstall.Enabled = -not $isInst
        $numSize.Enabled = -not $isInst
        $txtPw.Enabled = -not $isInst
        $txtPw2.Enabled = -not $isInst
        if ($isInst) { $btnInstall.Text = '이미 설치됨' } else { $btnInstall.Text = '원클릭 설치' }
    }.GetNewClosure()

    $btnInstall.Add_Click({
        if ($txtPw.Text -eq '') { [System.Windows.Forms.MessageBox]::Show('비밀번호를 입력하세요.', 'SECRET') | Out-Null; return }
        if ($txtPw.Text -ne $txtPw2.Text) { [System.Windows.Forms.MessageBox]::Show('비밀번호가 서로 다릅니다.', 'SECRET') | Out-Null; return }
        if ($txtPw.Text.Contains('"')) { [System.Windows.Forms.MessageBox]::Show('비밀번호에 큰따옴표(")는 쓸 수 없습니다.', 'SECRET') | Out-Null; return }
        if ($txtPw.Text.Length -lt 8) {
            $r = [System.Windows.Forms.MessageBox]::Show('짧은 비밀번호는 쉽게 뚫릴 수 있습니다. 8자 이상을 권장합니다.' + "`n`n이대로 진행할까요?", 'SECRET', 'YesNo', 'Warning')
            if ($r -ne 'Yes') { return }
        }
        $btnInstall.Enabled = $false; $btnDelete.Enabled = $false
        try {
            Install-SecretFolder -Config $cfg -SizeGB ([int]$numSize.Value) -Password $txtPw.Text -Log $writeLog
            [System.Windows.Forms.MessageBox]::Show('설치가 완료되었습니다.', 'SECRET') | Out-Null
        } catch {
            & $writeLog "오류: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("설치 중 오류가 발생했습니다.`n$($_.Exception.Message)", 'SECRET', 'OK', 'Error') | Out-Null
        } finally {
            $txtPw.Clear(); $txtPw2.Clear()
            $btnDelete.Enabled = $true
            & $refreshState
        }
    })

    $btnDelete.Add_Click({
        $btnInstall.Enabled = $false; $btnDelete.Enabled = $false
        try {
            $ask = {
                param($prompt)
                Add-Type -AssemblyName Microsoft.VisualBasic
                $v = [Microsoft.VisualBasic.Interaction]::InputBox($prompt, 'SECRET', '')
                if ($v -eq '') { return $null } else { return $v }
            }
            $confirm = { param($m) ([System.Windows.Forms.MessageBox]::Show($m, 'SECRET', 'YesNo', 'Warning') -eq 'Yes') }
            $info    = { param($m) [System.Windows.Forms.MessageBox]::Show($m, 'SECRET') | Out-Null; & $writeLog $m }
            $r = Remove-SecretFolder -Config $cfg -AskPassword $ask -Confirm $confirm -Info $info
            & $writeLog "삭제 결과: $r"
        } catch {
            & $writeLog "오류: $($_.Exception.Message)"
        } finally {
            $btnInstall.Enabled = $true; $btnDelete.Enabled = $true
            & $refreshState
        }
    })

    & $refreshState
    if ($installed) { & $writeLog '이미 설치되어 있습니다. secret / hide 로 사용하세요.' }

    if ($BuildOnly) { $form.Dispose(); return }
    [void]$form.ShowDialog()
}

# ==================================================================
# 자체 점검
# ==================================================================
function Invoke-SelfTest {
    $fail = 0
    function Check($name, $cond) {
        if ($cond) { Write-Host "  PASS  $name" }
        else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:stTestFail++ }
    }
    $script:stTestFail = 0

    Write-Host 'find tools:'
    Check 'AutoHotkey found'      ([bool](Find-AutoHotkey))
    Check 'VeraCrypt found'       ([bool](Find-VeraCrypt))
    Check 'VeraCrypt Format found'([bool](Find-VeraCryptFormat))

    $tmpRoot = Join-Path $env:TEMP ('sf_selftest_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    $cfg = Get-Config -InstallRoot $tmpRoot
    Write-Host "temp root: $tmpRoot"
    try {
        New-Vault -Config $cfg -SizeGB 1 -Password 'test1234' -Log { param($m) Write-Host "    $m" }
        Check 'vault created' (Test-Path $cfg.VaultPath)

        # 마운트해서 빈 상태 확인
        $vc = Find-VeraCrypt
        $L = Get-FreeDriveLetter
        Start-Process $vc -Wait -ArgumentList @('/v', "`"$($cfg.VaultPath)`"", '/l', $L, '/hash', 'sha512', '/p', 'test1234', '/q', '/s', '/h', 'n') | Out-Null
        $emptyCount = Get-VaultUserItemCount -DriveLetter $L -Config $cfg
        Check 'empty vault -> 0 user items' ($emptyCount -eq 0)
        Set-Content "${L}:\hello.txt" 'hi'
        $oneCount = Get-VaultUserItemCount -DriveLetter $L -Config $cfg
        Check 'one file -> 1 user item' ($oneCount -eq 1)

        # 파일이 있을 때 삭제 시도 → 'notempty' 여야 함 (마운트된 상태로 검사)
        $rBusy = Remove-SecretFolder -Config $cfg `
                    -AskPassword { param($p) 'test1234' } `
                    -Confirm { param($m) $true } `
                    -Info { param($m) }
        Check "non-empty vault -> 'notempty' (got '$rBusy')" ($rBusy -eq 'notempty')
        Check 'vault still exists after notempty' (Test-Path $cfg.VaultPath)

        # 파일을 지우고(마운트된 상태) 언마운트
        Remove-Item "${L}:\hello.txt" -Force
        Start-Process $vc -Wait -ArgumentList @('/u', $L, '/q', '/s') | Out-Null

        # 빈 금고 삭제 경로 (자동 응답)
        $r = Remove-SecretFolder -Config $cfg `
                -AskPassword { param($p) 'test1234' } `
                -Confirm { param($m) $true } `
                -Info { param($m) Write-Host "    info: $m" }
        Check "delete empty vault -> 'deleted' (got '$r')" ($r -eq 'deleted')
        Check 'install root removed' (-not (Test-Path $cfg.InstallRoot))
    } finally {
        if (Test-Path $tmpRoot) {
            attrib -h -s "$tmpRoot" 2>$null
            Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host 'gui build:'
    try { Show-MainForm -BuildOnly; Check 'form builds without error' $true }
    catch { Check "form builds ($_)" $false }

    Write-Host ''
    if ($script:stTestFail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green }
    else { Write-Host "$($script:stTestFail) FAILED" -ForegroundColor Red; exit 1 }
}

# ==================================================================
if ($SelfTest) { Invoke-SelfTest }
else { Show-MainForm }

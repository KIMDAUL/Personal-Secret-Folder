<#
    Harden-Traces.ps1 — 암호화 밖에 남는 "흔적" 예방 설정 (사용자 단위, 관리자 불필요)

    기본 적용 항목 (모두 현재 사용자 HKCU, 일상 사용에 지장 적음):
      1) 최근 항목/바로 가기 목록 기록 끄기      (Start_TrackDocs=0, NoRecentDocsHistory=1)
      2) 클립보드 기록(Win+V) 끄기               (EnableClipboardHistory=0)
      + 기존 흔적 정리: Recent 목록, 클립보드 비우기

    옵션 -Thumbnails (주의: 컴퓨터 전체에 영향):
      3) 썸네일 미리보기 끄기 (IconsOnly=1)      → 캐시 미생성
         ※ Windows는 폴더별 썸네일 끄기를 지원하지 않아, 켜면 "모든 폴더"의
            사진·영상 미리보기가 아이콘으로 바뀝니다. 금고에 이미지를 자주 넣는
            경우에만 권장합니다.

    사용:
      기본 적용:        powershell -ExecutionPolicy Bypass -File Harden-Traces.ps1
      썸네일까지 끄기:  powershell -ExecutionPolicy Bypass -File Harden-Traces.ps1 -Thumbnails
      되돌림:           powershell -ExecutionPolicy Bypass -File Harden-Traces.ps1 -Undo

    주의:
      - "삭제"는 완전 소거가 아닙니다(특히 SSD). 이미 만들어진 흔적의 잔재는 남을 수 있습니다.
      - 모든 흔적을 확실히 덮는 근본책은 디스크 전체 암호화(BitLocker)입니다.
      - 되돌림(-Undo)은 Windows 기본값으로 복원합니다.
#>
[CmdletBinding()]
param(
    [switch]$Undo,
    [switch]$Thumbnails
)

$Adv    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$PolExp = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$Clip   = 'HKCU:\Software\Microsoft\Clipboard'

function Set-Reg($path, $name, $value) {
    # 일부 정책 키(Policies\*)는 계정 권한상 만들 수 없으므로 실패해도 중단하지 않음
    try {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host "  (건너뜀) $name 설정 불가: $($_.Exception.Message.Split([char]10)[0])"
        return $false
    }
}
function Remove-Reg($path, $name) {
    if (Test-Path $path) { Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue }
}
function Restart-Explorer {
    Write-Host '  탐색기 새로고침 중...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}
function Clear-RecentAndClipboard {
    foreach ($sub in @('Recent', 'Recent\AutomaticDestinations', 'Recent\CustomDestinations')) {
        $p = Join-Path $env:APPDATA "Microsoft\Windows\$sub"
        if (Test-Path $p) { Get-ChildItem $p -Force -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    }
    try { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::Clear() } catch {}
}
function Clear-ThumbnailCache {
    # 탐색기가 파일을 잠그므로, 종료된 동안 삭제해야 함
    $expl = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    if (Test-Path $expl) { Get-ChildItem $expl -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
}

if ($Undo) {
    Write-Host '되돌리는 중 (Windows 기본값 복원)...'
    Set-Reg    $Adv    'Start_TrackDocs' 1 | Out-Null
    Set-Reg    $Adv    'IconsOnly'       0 | Out-Null
    Remove-Reg $PolExp 'NoRecentDocsHistory'
    Set-Reg    $Clip   'EnableClipboardHistory' 1 | Out-Null
    Restart-Explorer
    Write-Host '완료: 최근 항목/썸네일/클립보드 기록이 다시 켜졌습니다.'
    return
}

Write-Host '흔적 예방 설정 적용 중...'
Set-Reg $Adv    'Start_TrackDocs'         0 | Out-Null   # 최근 문서 추적 끄기 (핵심)
Set-Reg $PolExp 'NoRecentDocsHistory'     1 | Out-Null   # 정책으로도 끄기 (권한 없으면 자동 건너뜀)
Set-Reg $Clip   'EnableClipboardHistory'  0 | Out-Null   # 클립보드 기록 끄기
if ($Thumbnails) {
    Set-Reg $Adv 'IconsOnly' 1 | Out-Null                # 썸네일 대신 아이콘만 (컴퓨터 전체)
}
Write-Host '  레지스트리 설정 완료.'

Write-Host '기존 흔적 정리 중...'
Clear-RecentAndClipboard
if ($Thumbnails) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Clear-ThumbnailCache
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}
Write-Host '  정리 완료.'

Write-Host ''
Write-Host '적용된 항목:'
Write-Host '  - 최근 항목/바로 가기 목록 기록 끄기'
Write-Host '  - 클립보드 기록(Win+V) 끄기'
if ($Thumbnails) {
    Write-Host '  - 썸네일 미리보기 끄기 (모든 폴더에서 아이콘만 표시)'
} else {
    Write-Host '  - (썸네일은 그대로 둠. 끄려면 -Thumbnails 옵션 사용 — 컴퓨터 전체에 영향)'
}
Write-Host ''
Write-Host '참고:'
Write-Host '  - 되돌리려면 -Undo 옵션으로 실행하세요.'
Write-Host '  - 검색 색인: 금고는 기본적으로 색인되지 않지만, 확실히 하려면'
Write-Host '    제어판 > 색인 옵션 > 수정 에서 금고 드라이브가 빠져 있는지 확인하세요.'
Write-Host '  - 흔적을 완전히 덮으려면 디스크 전체 암호화(BitLocker)가 근본책입니다.'

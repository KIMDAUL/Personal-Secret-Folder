#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
Persistent
DetectHiddenWindows true

; SECRET 금고 (VeraCrypt 암호화 컨테이너)
; - 바탕화면에서 secret  : SECRET 아이콘 표시 → 더블클릭 → 비밀번호 입력 → 금고 열림
; - 바탕화면에서 hide    : 금고 잠금 + 아이콘 제거
; - 바탕화면에서 changepw: 비밀번호 변경
; - 로그인 시(/boot)     : 금고 잠금 + 아이콘 제거
; 키 입력은 기록하지 않으며, 바탕화면이 활성화된 경우에만 위 세 단어에 반응함 (대소문자 무관)

VC           := EnvGet("ProgramFiles") "\VeraCrypt\VeraCrypt.exe"
VaultPath    := A_ScriptDir "\vault.hc"
MarkerName   := ".secret_marker"
ShortcutPath := A_Desktop "\SECRET.lnk"
AppTitle     := "SECRET"
WM_UNLOCK    := 0x8001
Busy         := false
StatePath    := A_ScriptDir "\state.ini"   ; 실패 횟수 / 잠금 해제 시각 (재시작해도 유지)
MaxFails     := 3
LockMinutes  := 5

mode := A_Args.Length ? A_Args[1] : ""
other := FindOtherInstance()
if (mode = "/unlock") {
    if other {
        ; 이미 대기 중인 인스턴스에 잠금 해제를 맡기고 종료
        PostMessage(WM_UNLOCK, 0, 0, , "ahk_id " other)
        ExitApp
    }
    SetTimer(Unlock, -100)
} else if other {
    ExitApp   ; 이미 실행 중
}
if (mode = "/boot") {
    try FileDelete(ShortcutPath)
    Lock(true)
}
OnMessage(WM_UNLOCK, (*) => (SetTimer(Unlock, -1), 1))

#HotIf IsDesktop()
; * 즉시 실행, B0 입력 글자 지우지 않음, Z 실행 후 입력 버퍼 초기화
:*B0Z:secret::
{
    if !FileExist(ShortcutPath)
        FileCreateShortcut(A_AhkPath, ShortcutPath, A_ScriptDir, '"' A_ScriptFullPath '" /unlock', "", "shell32.dll", , 4)
}

:*B0Z:hide::
{
    if Lock()
        try FileDelete(ShortcutPath)
}

:*B0Z:changepw::
{
    SetTimer(ChangePassword, -1)
}
#HotIf

IsDesktop() => WinActive("ahk_class Progman") || WinActive("ahk_class WorkerW")

FindOtherInstance() {
    for h in WinGetList("ahk_class AutoHotkey")
        if (h != A_ScriptHwnd && InStr(WinGetTitle(h), A_ScriptFullPath))
            return h
    return 0
}

; 금고가 열려 있는 드라이브 문자 (없으면 "")
FindMounted() {
    for L in StrSplit(DriveGetList("FIXED"))
        if FileExist(L ":\" MarkerName)
            return L
    return ""
}

PickLetter() {
    used := DriveGetList()
    for L in StrSplit("SRQPONMLKJIHGTUVWXYZ")
        if !InStr(used, L)
            return L
    return ""
}

Unlock(*) {
    global Busy
    if Busy
        return
    Busy := true
    try DoUnlock()
    Busy := false
}

DoUnlock() {
    if (L := FindMounted()) {
        Run('explorer.exe ' L ':\')
        return
    }
    Loop {
        if CheckLocked(AppTitle)
            return
        ib := InputBox("비밀번호를 입력하세요.", AppTitle, "Password w280 h120")
        if (ib.Result != "OK" || ib.Value = "")
            return
        if !(L := PickLetter()) {
            MsgBox("사용 가능한 드라이브 문자가 없습니다.", AppTitle, "Iconx")
            return
        }
        ToolTip("확인 중...")
        ; /hash sha512: 금고 생성 때 쓴 방식만 시도 (생략하면 모든 방식을 시도해 오답 판정이 느려짐)
        RunWait('"' VC '" /v "' VaultPath '" /l ' L ' /hash sha512 /p "' ib.Value '" /q /s /h n', , "Hide")
        ToolTip()
        if (FindMounted() = L) {
            ResetFails()
            Run('explorer.exe ' L ':\')
            return
        }
        if !ReportFail(AppTitle, "비밀번호가 올바르지 않습니다.")
            return
    }
}

; ---- 입력 잠금 (MaxFails번 틀리면 LockMinutes분) ----
LockRemaining() {
    untilTs := IniRead(StatePath, "lock", "until", "")
    if (untilTs = "")
        return 0
    try secs := DateDiff(untilTs, A_Now, "Seconds")
    catch
        return 0
    return secs > 0 ? secs : 0
}

; 잠겨 있으면 안내하고 true
CheckLocked(title) {
    if !(secs := LockRemaining())
        return false
    MsgBox(Format("비밀번호를 {1}번 틀려서 입력이 잠겨 있습니다.`n{2}분 {3}초 후에 다시 시도하세요.", MaxFails, secs // 60, Mod(secs, 60)), title, "Icon!")
    return true
}

; 실패 1회 기록 후 안내. 아직 시도 가능하면 true, 방금 잠겼으면 false
ReportFail(title, msg) {
    fails := Integer(IniRead(StatePath, "lock", "fails", 0)) + 1
    if (fails >= MaxFails) {
        IniWrite(DateAdd(A_Now, LockMinutes, "Minutes"), StatePath, "lock", "until")
        IniWrite(0, StatePath, "lock", "fails")
        MsgBox(Format("{1}`n`n{2}번 틀려서 {3}분간 입력이 잠깁니다.", msg, MaxFails, LockMinutes), title, "Iconx")
        return false
    }
    IniWrite(fails, StatePath, "lock", "fails")
    MsgBox(Format("{1} (남은 시도: {2}회)", msg, MaxFails - fails), title, "Icon!")
    return true
}

ResetFails() {
    IniWrite(0, StatePath, "lock", "fails")
    IniWrite("", StatePath, "lock", "until")
}

; 금고 잠금. 성공(또는 이미 잠김)하면 true
Lock(silent := false) {
    if !(L := FindMounted())
        return true
    CloseExplorerOn(L)
    Sleep(300)
    RunWait('"' VC '" /u ' L ' /q /s', , "Hide")
    if !FindMounted()
        return true
    if silent
        return false
    if (MsgBox("금고 안의 파일이 아직 열려 있어서 잠글 수 없습니다.`n`n강제로 잠글까요? 저장하지 않은 내용은 사라질 수 있습니다.", AppTitle, "YesNo Icon! Default2") != "Yes")
        return false
    RunWait('"' VC '" /u ' L ' /f /q /s', , "Hide")
    return !FindMounted()
}

CloseExplorerOn(L) {
    try {
        for w in ComObject("Shell.Application").Windows {
            try {
                if (SubStr(w.Document.Folder.Self.Path, 1, 2) = L ":")
                    w.Quit()
            }
        }
    }
}

ChangePassword(*) {
    global Busy
    if Busy
        return
    Busy := true
    try DoChangePassword()
    Busy := false
}

DoChangePassword() {
    t := AppTitle " - 비밀번호 변경"
    if CheckLocked(t)
        return
    ; VeraCrypt는 금고가 열려 있으면 비밀번호 변경을 거부함 → 먼저 잠금
    if FindMounted() {
        if (MsgBox("금고가 열려 있으면 비밀번호를 바꿀 수 없습니다.`n`n금고를 잠그고 계속할까요?", t, "YesNo Icon?") != "Yes")
            return
        if !Lock() {
            MsgBox("금고를 잠그지 못해서 비밀번호 변경을 취소했습니다.", t, "Icon!")
            return
        }
    }
    if ProcessExist("VeraCrypt.exe") {
        MsgBox("VeraCrypt 프로그램이 열려 있습니다.`nVeraCrypt를 닫은 뒤 다시 시도해 주세요.", t, "Icon!")
        return
    }
    cur := InputBox("현재 비밀번호를 입력하세요.", t, "Password w300 h120")
    if (cur.Result != "OK" || cur.Value = "")
        return
    new1 := InputBox("새 비밀번호를 입력하세요.", t, "Password w300 h120")
    if (new1.Result != "OK" || new1.Value = "")
        return
    if InStr(new1.Value, '"') {
        MsgBox('비밀번호에는 큰따옴표(")를 쓸 수 없습니다.', t, "Icon!")
        return
    }
    new2 := InputBox("새 비밀번호를 한 번 더 입력하세요.", t, "Password w300 h120")
    if (new2.Result != "OK")
        return
    if (new1.Value !== new2.Value) {
        MsgBox("새 비밀번호가 서로 다릅니다. 처음부터 다시 해 주세요.", t, "Icon!")
        return
    }
    ToolTip("비밀번호를 바꾸는 중입니다...")
    result := VcChangePassword(cur.Value, new1.Value)
    ToolTip()
    if (result = "ok") {
        ResetFails()
        MsgBox("비밀번호가 변경되었습니다.`n`n새 비밀번호를 잊으면 금고를 열 수 없으니 따로 적어 두세요.", t, "Iconi")
    } else if (result = "wrongpw")
        ReportFail(t, "현재 비밀번호가 틀렸습니다.")   ; 비밀번호 변경으로 무제한 대입하는 것도 막음
    else
        MsgBox("비밀번호를 바꾸지 못했습니다.`n`n" result, t, "Iconx")
}

; VeraCrypt의 'Change Volume Password' 창을 자동 조작
; (비밀번호는 명령줄에 노출되지 않음). 결과: "ok" / "wrongpw" / 오류 메시지
VcChangePassword(cur, new) {
    Run('"' VC '"', , , &pid)
    result := "VeraCrypt 창을 열지 못했습니다."
    main := WinWait("ahk_pid " pid " ahk_class VeraCryptCustomDlg", , 10)
    dlg := 0
    if main {
        ControlSetText(VaultPath, "Edit1", main)
        Sleep(200)
        PostMessage(0x111, 40015, 0, , main)   ; WM_COMMAND: Volumes > Change Volume Password
        start := A_TickCount
        while !dlg && (A_TickCount - start < 10000) {
            Sleep(100)
            dlg := WinExist("Change Password or Keyfiles ahk_pid " pid)
            if !dlg && (msg := VcMessage(pid, main)) {   ; 변경 창 대신 오류가 뜬 경우
                result := msg.text
                PressButton("Button1", msg.hwnd)
                break
            }
        }
    }
    if dlg {
        try ControlChooseString("SHA512-PBKDF2", "ComboBox1", dlg)   ; 현재 KDF 지정 → 오답 판정 빨라짐
        ControlSetText(cur, "Edit1", dlg)   ; 현재 비밀번호
        ControlSetText(new, "Edit3", dlg)   ; 새 비밀번호
        ControlSetText(new, "Edit4", dlg)   ; 새 비밀번호 확인
        Sleep(200)
        PressButton("Button9", dlg)         ; OK
        result := "시간이 초과되었습니다."
        pressed := Map()
        start := A_TickCount
        while (A_TickCount - start < 90000) {
            Sleep(100)
            if !(msg := VcMessage(pid, main, dlg))
                continue
            h := msg.hwnd
            ; 창이 막 떠서 신호를 놓칠 수 있으므로, 닫힐 때까지 0.5초마다 다시 누름
            if pressed.Has(h) && (A_TickCount - pressed[h] < 500)
                continue
            pressed[h] := A_TickCount
            if InStr(msg.text, "hort password") || InStr(msg.title, "Random Pool") {
                PressButton("Button1", h)   ; 짧은 비밀번호 경고 → 예 / 무작위 데이터 수집 → Continue
                continue
            }
            if InStr(msg.text, "successfully changed")
                result := "ok"
            else if InStr(msg.text, "ncorrect password")
                result := "wrongpw"
            else
                result := msg.text
            PressButton("Button1", h)       ; 확인
            break
        }
    }
    Sleep(300)
    if dlg && WinExist("ahk_id " dlg)
        PressButton("Button10", dlg)        ; Cancel (오답 등으로 변경 창이 남은 경우)
    Sleep(300)
    if ProcessExist(pid)
        ProcessClose(pid)
    return result
}

; VeraCrypt가 띄운 메시지 창(#32770) 하나를 찾아 {hwnd, title, text} 반환 (없으면 0)
VcMessage(pid, exclude*) {
    for h in WinGetList("ahk_pid " pid " ahk_class #32770") {
        skip := false
        for x in exclude
            if (h = x)
                skip := true
        if skip
            continue
        try {
            title := WinGetTitle(h)
            text := WinGetText(h)
        } catch
            continue
        if (text = "" || InStr(text, "Please wait"))
            continue
        ; 메시지 본문 = Static 컨트롤 중 가장 긴 글
        body := ""
        try for c in WinGetControls(h)
            if InStr(c, "Static") && StrLen(s := ControlGetText(c, h)) > StrLen(body)
                body := s
        return {hwnd: h, title: title, text: body != "" ? Trim(body) : Trim(text)}
    }
    return 0
}

; 버튼 클릭 대신 '버튼이 눌렸다'는 신호(WM_COMMAND)를 대화상자에 직접 보냄 → 창이 숨겨져 있어도 동작
PressButton(btn, h) {
    try {
        b := ControlGetHwnd(btn, h)
        PostMessage(0x111, DllCall("GetDlgCtrlID", "ptr", b, "int"), b, , "ahk_id " h)
        return true
    }
    return false
}

' v2rayn-proxy-guard: windowless launcher.
' Why this exists: a scheduled task that runs powershell.exe directly still
' flashes a console window for a moment on every trigger. wscript.exe has no
' console at all, so launching PowerShell from here shows nothing.
'
' Usage: wscript.exe run-hidden.vbs "<script.ps1>" [extra args...]
' Everything after the .vbs path is passed to powershell.exe, each argument
' individually quoted (paths may contain spaces).

Set sh = CreateObject("Wscript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden"
For i = 0 To Wscript.Arguments.Count - 1
    cmd = cmd & " """ & Wscript.Arguments(i) & """"
Next
sh.Run cmd, 0, False

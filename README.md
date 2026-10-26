# Setup Go for Windows

- [MSYS2 UCRT64](https://www.msys2.org/)
- [GCC](https://gcc.gnu.org/)
- [Go](https://go.dev/)
- [gopls](https://go.dev/gopls/)
- [Zed](https://zed.dev/)

## Run setup

On an Intel or AMD 64-bit Windows 11 PC, open a PowerShell tab in Windows Terminal and paste:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ((New-Object Net.WebClient -Property @{Encoding=[Text.Encoding]::UTF8}).DownloadString('https://raw.githubusercontent.com/tsukinoko-kun/windows-go-setup/refs/heads/main/setup.ps1'))"
```

Approve the Windows administrator prompt when the Go installer requests it. After setup finishes, open a new terminal and restart Zed to use the updated `PATH`.

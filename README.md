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

Setup reuses an existing Go installation or extracts the official Go ZIP to `%LOCALAPPDATA%\Programs\Go` without administrator privileges. It configures `PATH` automatically. After setup finishes, open a new terminal and restart Zed to use the updated `PATH`.

## Try Go with raylib

From this repository in a new PowerShell terminal, run:

```powershell
cd raylib-example
go run .
```

The first run downloads dependencies and compiles raylib's bundled C code using GCC. This can take a few minutes. A window should open with a blue circle and "Go + raylib works!". Press Escape to close it.

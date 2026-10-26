# Setup Go for Windows

- [MSYS2 UCRT64](https://www.msys2.org/)
- [GCC](https://gcc.gnu.org/)
- [Go](https://go.dev/)
- [gopls](https://go.dev/gopls/)
- [Zed](https://zed.dev/)

## Run setup

On an Intel or AMD 64-bit PC running Windows 10 version 1903 or newer, or Windows 11, open Windows PowerShell and paste:

```powershell
$setupScript = Join-Path $env:TEMP ('windows-go-setup-' + [Guid]::NewGuid().ToString('N') + '.ps1')
curl.exe --tlsv1.2 --tls-max '1.2' -fL -o $setupScript 'https://raw.githubusercontent.com/tsukinoko-kun/windows-go-setup/refs/heads/main/setup.ps1'
if ($LASTEXITCODE -eq 0) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript
} else {
    throw 'Could not download setup.ps1. See the curl error above.'
}
```

Setup reuses an existing Go installation or extracts the official Go ZIP to `%LOCALAPPDATA%\Programs\Go` without administrator privileges. It configures `PATH` automatically. After setup finishes, open a new terminal and restart Zed to use the updated `PATH`.

## Try Go with raylib

From this repository in a new PowerShell terminal, run:

```powershell
cd raylib-example
go run .
```

The first run downloads dependencies and compiles raylib's bundled C code using GCC. This can take a few minutes. A window should open with a blue circle and "Go + raylib works!". Press Escape to close it.

# Demo del respaldo de configuracion de FRR (playbook 05) para Windows.
# Llama a scripts/demo-respaldo.sh dentro de WSL (Ansible no corre nativo en Windows).
#
# Uso, desde cualquier carpeta:
#   powershell -ExecutionPolicy Bypass -File .\scripts\demo-respaldo.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\demo-respaldo.ps1 -Detalle
#
# Requisitos: Docker Desktop con el laboratorio levantado, WSL con una distro Linux
# y ansible-playbook instalado en ella.
param(
    [string]$Distro = '',
    [switch]$Detalle
)

$repo = Split-Path -Parent $PSScriptRoot
function Falla($t) { Write-Host ""; Write-Host "ERROR: $t" -ForegroundColor Red; exit 1 }

docker ps *> $null
if ($LASTEXITCODE -ne 0) { Falla "Docker no responde. Abrir Docker Desktop y reintentar." }

$distros = ((wsl -l -q | Out-String) -replace "`0", '') -split "`r?`n" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notlike 'docker-desktop*' }
if (-not $distros) { Falla "No hay ninguna distribucion WSL instalada. Instalar una con: wsl --install -d Ubuntu" }
if (-not $Distro) { if ($distros -contains 'Ubuntu-24.04') { $Distro = 'Ubuntu-24.04' } else { $Distro = @($distros)[0] } }
elseif ($distros -notcontains $Distro) { Falla "No encuentro la distribucion WSL '$Distro'. Disponibles: $($distros -join ', ')" }

$repoWsl = (wsl -d $Distro -- wslpath -a $repo.Replace('\', '/') | Out-String).Trim()
if (-not $repoWsl) { Falla "No pude convertir la ruta del repo a WSL." }
$flags = ''
if ($Detalle) { $flags = '--detalle' }

# sed quita los saltos de linea de Windows (CRLF) por si Git descargo el .sh con ellos.
# Solo comillas simples en el comando: PowerShell 5.1 pierde las dobles al llamar a wsl.exe,
# y asi tambien funcionan las rutas con espacios.
$q = $repoWsl.Replace("'", "'\''")
$cmd = "sed 's/`$//' '$q/scripts/demo-respaldo.sh' | REPO_ROOT='$q' bash -s -- $flags"
wsl -d $Distro -- bash -lc $cmd
exit $LASTEXITCODE

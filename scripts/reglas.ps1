# Publica las reglas e índices de Firestore desde GitHub (generado por Claude)
# Uso (descarga siempre la última versión de este script y lo ejecuta):
#   iwr https://raw.githubusercontent.com/cabal-studio/edhtools/main/scripts/reglas.ps1 -OutFile D:\Programacion\Juegos\edhtools\reglas.ps1; powershell -ExecutionPolicy Bypass -File D:\Programacion\Juegos\edhtools\reglas.ps1
$ErrorActionPreference = 'Continue'
$proj = 'D:\Programacion\Juegos\edhtools'
$raw  = 'https://raw.githubusercontent.com/cabal-studio/edhtools/main'
Set-Location $proj
New-Item -ItemType Directory -Force -Path "$proj\_configuracion" | Out-Null
Write-Host 'Descargando reglas e indices desde GitHub...' -ForegroundColor Cyan
foreach ($f in 'firestore.rules', 'firestore.indexes.json', 'firebase.json') {
  Invoke-WebRequest -Uri "$raw/$f" -OutFile "$proj\$f" -UseBasicParsing
}
& 'D:\Programacion\npm-global\firebase.cmd' deploy --only 'firestore:rules,firestore:indexes' --project edhtools --force 2>&1 |
  Tee-Object -FilePath "$proj\_configuracion\reglas.txt"
if ($LASTEXITCODE -eq 0) { Write-Host "`nReglas e indices publicados OK" -ForegroundColor Green }
else { Write-Host "`nERROR (ver _configuracion\reglas.txt). Avisa a Claude." -ForegroundColor Red }
Read-Host 'Presiona Enter para cerrar'

# Publica los cambios de Edhtools en https://edhtools.web.app (generado por Claude)
#   powershell -ExecutionPolicy Bypass -File D:\Programacion\Juegos\edhtools\publicar.ps1
$ErrorActionPreference = 'Continue'
$proj    = 'D:\Programacion\Juegos\edhtools'
$res     = "$proj\_configuracion"
$flutter = 'D:\Programacion\FlutterSDK\flutter\bin\flutter.bat'
$fb      = 'D:\Programacion\npm-global\firebase.cmd'
$env:Path = "D:\Programacion\FlutterSDK\flutter\bin;D:\Programacion\npm-global;$env:Path"
Set-Location $proj
$log = "$res\publicar.txt"
"== Publicar $(Get-Date)" | Out-File $log -Encoding utf8
function Nota($t) { Write-Host $t -ForegroundColor Cyan; $t | Out-File $log -Append -Encoding utf8 }

& $flutter pub get 2>&1 | Out-Null
& $flutter analyze 2>&1 | Out-File "$res\publicar_analyze.txt" -Encoding utf8
$errores = (Select-String -Path "$res\publicar_analyze.txt" -Pattern '^\s*error -').Count
Nota "analyze: $errores error(es)"
if ($errores -gt 0) { Nota 'Hay errores de codigo: NO se publico. Avisa a Claude.'; Read-Host 'Enter para cerrar'; exit 1 }

& $flutter test 2>&1 | Out-File "$res\publicar_test.txt" -Encoding utf8
Nota ("test: " + $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'FALLAS (ver publicar_test.txt)' }))

& $flutter build web --release --no-wasm-dry-run 2>&1 | Out-File "$res\publicar_build.txt" -Encoding utf8
Nota ("build web: " + $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'ERROR (ver publicar_build.txt)' }))

& $fb deploy --only "hosting,firestore:rules" --project edhtools 2>&1 | Out-File "$res\publicar_deploy.txt" -Encoding utf8
Nota ("deploy: " + $(if ($LASTEXITCODE -eq 0) { 'OK -> https://edhtools.web.app (recarga la pagina)' } else { 'ERROR (ver publicar_deploy.txt)' }))
Read-Host 'Presiona Enter para cerrar'

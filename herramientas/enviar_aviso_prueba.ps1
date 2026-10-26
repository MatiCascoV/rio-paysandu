# Fase 4, paso 4: manda un aviso push de prueba, igual al de avisos.yml con prueba=true.
# Solo a los temas de prueba (prefijo prueba-): no puede mandar a los temas reales.
# Mensaje SOLO DE DATOS, sin título ni texto: la app arma la notificación con actual.json.
# Usa la sesión de gcloud del dueño (gcloud auth login); no guarda ninguna clave.
#
# Uso (la app compilada con --dart-define=TEMAS_PRUEBA=true):
#   .\herramientas\enviar_aviso_prueba.ps1 -Tipo urgente -Nivel alerta
#   .\herramientas\enviar_aviso_prueba.ps1 -Tipo urgente -Nivel evacuacion   # dos mensajes, uno por tema urgente
#   .\herramientas\enviar_aviso_prueba.ps1 -Tipo resumen -Fuente prefectura
# Si falla un mensaje se intentan igual los demás (sin reintentos) y al final termina con error
# diciendo cuál salió y cuál no.
# Cómo probar cada caso: docs/fase-4-informe-app.md.
param(
    [ValidateSet('urgente', 'resumen')][string]$Tipo = 'urgente',
    [ValidateSet('alerta', 'evacuacion')][string]$Nivel = 'alerta',
    [ValidateSet('prefectura', 'estacion')][string]$Fuente = 'prefectura'
)
$ErrorActionPreference = 'Stop'
$proyecto = 'mi-rio-uy-8ca81'
$gcloud = Join-Path $env:LOCALAPPDATA 'google-cloud-sdk-zip\google-cloud-sdk\bin\gcloud.cmd'

# Los temas salen de nombres fijos de acá, siempre con el prefijo de prueba.
$prefijo = 'prueba-'
$temaAlerta = "${prefijo}alerta-paysandu"
$temaEvacuacion = "${prefijo}evacuacion-paysandu"
$temaResumen = "${prefijo}resumen-paysandu"
foreach ($tema in @($temaAlerta, $temaEvacuacion, $temaResumen)) {
    if (-not $tema.StartsWith($prefijo)) { throw "El tema $tema no es de prueba: no se envía nada." }
}

# Igual que avisos.yml: siempre a temas directos, nunca a una condición de FCM. El urgente de
# evacuación son dos mensajes con los mismos datos, primero al tema de evacuación y después al de
# alerta. La app deja cada teléfono en un solo tema urgente. Si quedara en los dos (sincronización a
# medias), le llegan dos pushes, pero la app no repite el aviso (ultimo_nivel).
if ($Tipo -eq 'urgente') {
    $data = @{ tipo = 'urgente'; nivel = $Nivel; ciudad = 'paysandu' }
    if ($Nivel -eq 'alerta') {
        $temas = @($temaAlerta)
    } else {
        $temas = @($temaEvacuacion, $temaAlerta)
    }
    $prioridad = 'HIGH'
} else {
    $data = @{ tipo = 'resumen'; fuente = $Fuente; ciudad = 'paysandu' }
    $temas = @($temaResumen)
    $prioridad = 'NORMAL'
}

$token = (& $gcloud auth print-access-token).Trim()
$detalle = if ($Tipo -eq 'urgente') { $Nivel } else { $Fuente }
$fallidos = @()
$dudosos = @()
foreach ($tema in $temas) {
    $mensaje = @{ topic = $tema; data = $data; android = @{ priority = $prioridad } }
    $cuerpo = @{ message = $mensaje } | ConvertTo-Json -Depth 5
    # Sin reintentos: si FCM lo aceptó y se cortó la respuesta, reintentar duplicaría el aviso.
    # 15 s como máximo por mensaje, igual que avisos.yml (FCM contesta en menos de 1 s).
    try {
        $respuesta = Invoke-RestMethod -Method Post -TimeoutSec 15 `
            -Uri "https://fcm.googleapis.com/v1/projects/$proyecto/messages:send" `
            -Headers @{ Authorization = "Bearer $token"; 'x-goog-user-project' = $proyecto } `
            -ContentType 'application/json; charset=utf-8' -Body $cuerpo
        "Enviado $Tipo ($detalle, $prioridad) al tema $tema a las $(Get-Date -Format HH:mm:ss): $($respuesta.name)"
    } catch {
        # Solo el error y la respuesta de FCM (nunca los encabezados, que llevan el token).
        # Sin respuesta HTTP (tiempo agotado, conexión cortada) no se sabe si FCM lo recibió, salvo
        # que no se haya podido ni resolver el nombre ni conectar: ahí seguro que no salió.
        $sinRespuesta = $null -eq $_.Exception.Response
        $noConecto = "$($_.Exception.Status)" -in @('NameResolutionFailure', 'ConnectFailure')
        if ($sinRespuesta -and -not $noConecto) {
            Write-Warning "No se sabe si salió $Tipo ($detalle) al tema ${tema} (sin respuesta HTTP): $($_.Exception.Message)"
            $dudosos += $tema
        } else {
            Write-Warning "Falló el envío de $Tipo ($detalle) al tema ${tema}: $($_.Exception.Message) $($_.ErrorDetails.Message)"
            $fallidos += $tema
        }
    }
}
if ($fallidos.Count + $dudosos.Count -gt 0) {
    $salieron = @($temas | Where-Object { $fallidos -notcontains $_ -and $dudosos -notcontains $_ })
    $lista = { param($t) if ($t.Count -gt 0) { $t -join ', ' } else { 'ninguno' } }
    throw ("No salieron todos los mensajes. Fallaron: $(& $lista $fallidos). " +
        "No se sabe si salieron: $(& $lista $dudosos). Salieron: $(& $lista $salieron).")
}

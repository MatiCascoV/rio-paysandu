# Fase 4, paso 4: manda un aviso push de prueba, igual al de avisos.yml con prueba=true.
# Solo a los temas de prueba (prefijo prueba-): no puede mandar a los temas reales.
# Mensaje SOLO DE DATOS, sin título ni texto: la app arma la notificación con actual.json.
# Usa la sesión de gcloud del dueño (gcloud auth login); no guarda ninguna clave.
#
# Uso (la app compilada con --dart-define=TEMAS_PRUEBA=true):
#   .\herramientas\enviar_aviso_prueba.ps1 -Tipo urgente -Nivel alerta
#   .\herramientas\enviar_aviso_prueba.ps1 -Tipo urgente -Nivel evacuacion
#   .\herramientas\enviar_aviso_prueba.ps1 -Tipo resumen -Fuente prefectura
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

if ($Tipo -eq 'urgente') {
    $data = @{ tipo = 'urgente'; nivel = $Nivel; ciudad = 'paysandu' }
    if ($Nivel -eq 'alerta') {
        $destino = @{ topic = $temaAlerta }
    } else {
        # Igual que avisos.yml: el de evacuación va a quien esté en cualquiera de los dos temas urgentes
        # (cada teléfono está en uno solo, así le llega una sola vez).
        $destino = @{ condition = "'$temaAlerta' in topics || '$temaEvacuacion' in topics" }
    }
    $prioridad = 'HIGH'
} else {
    $data = @{ tipo = 'resumen'; fuente = $Fuente; ciudad = 'paysandu' }
    $destino = @{ topic = $temaResumen }
    $prioridad = 'NORMAL'
}

$token = (& $gcloud auth print-access-token).Trim()
$mensaje = $destino + @{ data = $data; android = @{ priority = $prioridad } }
$cuerpo = @{ message = $mensaje } | ConvertTo-Json -Depth 5
$respuesta = Invoke-RestMethod -Method Post `
    -Uri "https://fcm.googleapis.com/v1/projects/$proyecto/messages:send" `
    -Headers @{ Authorization = "Bearer $token"; 'x-goog-user-project' = $proyecto } `
    -ContentType 'application/json; charset=utf-8' -Body $cuerpo
$detalle = if ($Tipo -eq 'urgente') { $Nivel } else { $Fuente }
"Enviado $Tipo ($detalle, $prioridad) a $($destino.Values) a las $(Get-Date -Format HH:mm:ss): $($respuesta.name)"

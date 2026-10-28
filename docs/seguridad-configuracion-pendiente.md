# Configuración de seguridad pendiente (la aplica el dueño)

Estos cambios son de **configuración de GitHub y de Google Cloud**, no de archivos del repositorio, así
que no van en un PR: los aplica el dueño con su cuenta. Fuente: revisión de seguridad de la nube del
28/10/2026 (hallazgos M-01, M-02, B-06 y relacionados). Los comandos están pensados para PowerShell.

Variables comunes de Google Cloud:

```powershell
$G = "$env:LOCALAPPDATA\google-cloud-sdk-zip\google-cloud-sdk\bin\gcloud.cmd"
$P = "mi-rio-uy-8ca81"
```

## 1. M-02: borrar la "Browser key" sin uso (Media)

No hay app web en el proyecto, así que nadie usa esa clave, y no tiene restricción de sitio. Sin riesgo
para la app.

```powershell
& $G services api-keys delete 8e8fe6b8-539b-4081-aaaa-00f37ea39730 --project $P
```

Se puede recuperar durante 30 días con `& $G services api-keys undelete 8e8fe6b8-539b-4081-aaaa-00f37ea39730 --project $P`.

## 2. M-01: restringir la "Android key" (Media)

Hoy no tiene restricción de aplicación y habilita 27 APIs. Se restringe al paquete `uy.miriouy.app` y al
SHA-1 del certificado que firma el APK real.

1. Sacar el SHA-1 del keystore de firma (o de un APK ya firmado), sin dos puntos y en mayúsculas:

   ```powershell
   keytool -list -v -keystore <RUTA_AL_KEYSTORE>.jks -alias <ALIAS>
   # o: apksigner verify --print-certs app-release.apk
   ```

2. Aplicar la restricción:

   ```powershell
   & $G services api-keys update fd0b7bec-957f-4b82-b43f-1034704402ae --project $P `
     --allowed-application=sha1_fingerprint=<SHA1_EN_MAYUSCULA_SIN_DOS_PUNTOS>,package_name=uy.miriouy.app
   ```

   Si también se prueba con builds de depuración (la CI firma con la clave de depuración), la clave
   admite varias aplicaciones permitidas: repetir `--allowed-application` con el SHA-1 de depuración.

3. Registrar el mismo SHA-1 en Firebase (Configuración del proyecto, la app `uy.miriouy.app`).

4. Opcional, después de probar: reducir las APIs de la clave a las que usa la app (probablemente
   `firebaseinstallations.googleapis.com`, `fcmregistrations.googleapis.com` y `firebase.googleapis.com`):

   ```powershell
   & $G services api-keys update fd0b7bec-957f-4b82-b43f-1034704402ae --project $P `
     --api-target=service=firebaseinstallations.googleapis.com `
     --api-target=service=fcmregistrations.googleapis.com `
     --api-target=service=firebase.googleapis.com
   ```

> **Probar en el Redmi antes de dar el cambio por bueno.** Con la app instalada, abrir Ajustes y
> activar o desactivar la suscripción a un tema de avisos, y confirmar que sigue funcionando (y que el
> token de FCM se obtiene). Si aparece un error 403, la causa es que falta un servicio o el SHA-1 no
> coincide con el APK instalado: agregarlo con `--api-target=service=...` o `--allowed-application=...`.
> Si hay que volver atrás: `& $G services api-keys update fd0b7bec-957f-4b82-b43f-1034704402ae --project $P --clear-restrictions`.

## 3. B-06: exigir acciones fijadas por SHA (GitHub)

Los YAML ya fijan todas las acciones por SHA; esto impide que un cambio futuro use una etiqueta flotante.
Antes de activarlo, confirmar que todos los workflows (incluidos los nuevos `gitleaks.yml` y
`codeql.yml`) usen solo `uses:` con SHA completo, y que Dependabot siga abriendo PR de actualización.

```powershell
gh api -X PUT repos/MatiCascoV/rio-paysandu/actions/permissions -F enabled=true -f allowed_actions=all -F sha_pinning_required=true
```

Opcional, la política de aprobación de PR de colaboradores externos:

```powershell
gh api -X PUT repos/MatiCascoV/rio-paysandu/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors
```

## 4. B-06: checks obligatorios en el ruleset `proteger-main` (GitHub)

Agregar la regla `required_status_checks` con los checks de tests (y, ahora, de escaneo de secretos y
CodeQL). **Cuidado:** `app.yml` corre solo con cambios en `app/**` y `tests.yml` solo con cambios en
`lector/**`; un check requerido que no corre deja el PR bloqueado. Antes de exigirlos hay que quitar los
filtros `paths` de esos workflows en `pull_request` o agregar un job agregador que siempre corra.
`gitleaks.yml` y `codeql.yml` corren siempre en PR, así que se pueden exigir ya.

```powershell
# 1. Ver el ruleset y su id
gh api repos/MatiCascoV/rio-paysandu/rulesets --jq '.[] | {id, name}'
gh api repos/MatiCascoV/rio-paysandu/rulesets/<ID_DE_proteger-main> > ruleset.json

# 2. Agregar al arreglo "rules" de ruleset.json (y borrar del JSON los campos que la API no acepta al
#    hacer PUT: id, source, source_type, node_id, created_at, updated_at, _links, current_user_can_bypass):
#    {
#      "type": "required_status_checks",
#      "parameters": {
#        "strict_required_status_checks_policy": false,
#        "required_status_checks": [
#          { "context": "gitleaks" },
#          { "context": "Analizar (Python)" }
#        ]
#      }
#    }
#    Los nombres exactos del campo "context" son los de los jobs que se ven en un PR (Checks).

# 3. Aplicar
gh api -X PUT repos/MatiCascoV/rio-paysandu/rulesets/<ID_DE_proteger-main> --input ruleset.json
```

Las 0 aprobaciones de PR se dejan como están (un solo dueño).

## 5. Otros ajustes opcionales del informe

- Verificación de secretos de GitHub (patrones no de proveedor y validez):
  `gh api -X PATCH repos/MatiCascoV/rio-paysandu -F 'security_and_analysis[secret_scanning_non_provider_patterns][status]=enabled' -F 'security_and_analysis[secret_scanning_validity_checks][status]=enabled'`
- Activar "Keep my email addresses private" y "Block command line pushes that expose my email" en
  GitHub (Settings, Emails), y confirmar la verificación en dos pasos de las cuentas de GitHub y de Google.
- Retención de logs de Google Cloud a 90 días (B-07):
  `& $G logging buckets update _Default --location=global --retention-days=90 --project $P`

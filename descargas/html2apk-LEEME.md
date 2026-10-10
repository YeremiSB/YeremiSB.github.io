# html2apk.ps1 — de HTML a APK en un comando

Convierte cualquier archivo HTML en un APK de Android instalable, envolviéndolo en un
WebView nativo a pantalla completa.

**Sin Gradle. Sin Android Studio. Sin conexión a internet.** Solo usa las herramientas
que ya vienen con el SDK de Android: `aapt2`, `javac`, `d8`, `zipalign` y `apksigner`.

---

## Uso

```powershell
# Lo mínimo: el nombre y el identificador se deducen del archivo
.\html2apk.ps1 -Html .\mi_juego.html

# Con nombre, identificador propio, e instalación directa en el móvil por USB
.\html2apk.ps1 -Html .\mi_juego.html -Nombre "Mi Juego" -Package com.yo.mijuego -Instalar
```

> `-ExecutionPolicy Bypass` es obligatorio en este equipo (la política es `AllSigned`):
> `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\html2apk.ps1 -Html .\juego.html`

### Parámetros

| Parámetro | Por defecto | Para qué |
|---|---|---|
| `-Html` | *(obligatorio)* | El archivo .html a convertir |
| `-Nombre` | nombre del HTML | Nombre visible bajo el icono |
| `-Package` | `com.usuario.<nombre>` | Identificador de la app |
| `-Icono` | icono Win95 genérico | PNG propio para el icono |
| `-Salida` | `.\dist` | Carpeta donde dejar el APK |
| `-Orientacion` | `portrait` | `portrait`, `landscape`, `sensor`, `unspecified` |
| `-MinSdk` / `-TargetSdk` | `24` / `34` | Versiones de Android soportadas |
| `-Instalar` | — | Instala en el móvil conectado al terminar |

---

## Qué hace por dentro

1. **Comprueba** el HTML y deduce nombre, identificador y slug.
2. **Busca** el SDK, las build-tools, la plataforma y el JDK automáticamente.
3. **Genera** el proyecto Android completo: manifest, `MainActivity.java`,
   recursos y los 5 iconos (propio o genérico embebido en base64).
4. **Compila**: `aapt2 compile` → `aapt2 link` → `javac` → `d8`.
5. **Empaqueta** el `classes.dex` dentro del APK.
6. **Alinea** con `zipalign` y **firma** con `dev.keystore`.
7. **Verifica** la firma y muestra el resumen del APK.

Resultado típico: **17 KB** para un "hola mundo", **21 KB** para un juego completo.

Los proyectos generados quedan en `_build\<slug>\` por si quieres inspeccionarlos o
abrirlos con Android Studio.

---

## Firma

`dev.keystore` es una clave de desarrollo compartida por todas las apps que genere la
herramienta (PKCS12, alias `dev`, contraseña `android`).

Sirve para probar. Para publicar en Google Play necesitas tu propio keystore, y **debes
conservarlo**: Android identifica cada app por su clave de firma, así que si la pierdes
no podrás actualizar la app instalada, solo desinstalar y volver a instalar.

---

## Si vas a editar el script, cuidado con estas tres cosas

1. **El archivo necesita BOM UTF-8.** PowerShell 5.1 lee los `.ps1` como ANSI cuando no
   llevan BOM, y los acentos de los comentarios rompen el parser. Si editas el archivo
   con una herramienta que quite el BOM, vuelve a ponérselo:
   ```powershell
   $p = ".\html2apk.ps1"
   $t = [System.IO.File]::ReadAllText((Resolve-Path $p), (New-Object System.Text.UTF8Encoding($false)))
   [System.IO.File]::WriteAllText((Resolve-Path $p), $t, (New-Object System.Text.UTF8Encoding($true)))
   ```
2. **Las claves de una tabla hash no distinguen mayúsculas** en PowerShell 5.1, así que
   `@{'á'='a'; 'Á'='A'}` da error de clave duplicada. Para quitar acentos se usan códigos
   de carácter (`[char]0x00E1`), que es lo que hace la función `Quitar-Acentos`.
3. **Los archivos generados se escriben sin BOM** (`Escribir-Utf8SinBom`), porque `javac`
   falla si el `.java` empieza con BOM.

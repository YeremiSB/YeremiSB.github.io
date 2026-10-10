<#
.SYNOPSIS
    Convierte cualquier archivo HTML en un APK de Android instalable.

.DESCRIPTION
    Envuelve tu HTML en un WebView nativo a pantalla completa y compila el APK usando
    solo las herramientas del SDK de Android: aapt2, javac, d8, zipalign y apksigner.
    No necesita Gradle, ni Android Studio, ni conexion a internet.

.PARAMETER Html
    Ruta del archivo .html que quieres convertir. Es el unico parametro obligatorio.

.PARAMETER Nombre
    Nombre visible de la app (el que sale bajo el icono). Por defecto, el nombre del HTML.

.PARAMETER Package
    Identificador Java, ej. com.tunombre.miapp. Por defecto se deriva del nombre.
    OJO: una vez instalada la app, este identificador no deberia cambiar.

.PARAMETER Icono
    PNG opcional para el icono. Si no se indica, se usa uno generico estilo Windows 95.

.PARAMETER Salida
    Carpeta donde dejar el APK. Por defecto "<carpeta del script>\dist".

.PARAMETER Orientacion
    portrait (por defecto), landscape, sensor o unspecified.

.PARAMETER Instalar
    Si se indica, instala el APK en el movil conectado por USB al terminar.

.EXAMPLE
    .\html2apk.ps1 -Html C:\ruta\mi_juego.html

.EXAMPLE
    .\html2apk.ps1 -Html .\juego.html -Nombre "Mi Juego" -Package com.yo.mijuego -Instalar
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Html,

    [string]$Nombre  = "",
    [string]$Package = "",
    [string]$Icono   = "",
    [string]$Salida  = "",
    [ValidateSet('portrait', 'landscape', 'sensor', 'unspecified')]
    [string]$Orientacion = 'portrait',
    [int]$MinSdk    = 24,
    [int]$TargetSdk = 34,
    [switch]$Instalar
)

$ErrorActionPreference = 'Stop'
Write-Host ""

# =====================================================================
#  Utilidades
# =====================================================================
function Paso($t) { Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  OK  $t" -ForegroundColor Green }
function Aviso($t){ Write-Host "  !!  $t" -ForegroundColor Yellow }
function Morir($t){ Write-Host "  XX  $t" -ForegroundColor Red; exit 1 }

function Quitar-Acentos($s) {
    # Por codigo de caracter y no con una tabla hash: en PowerShell 5.1 las claves
    # de un hash no distinguen mayusculas y las vocales acentuadas colisionan.
    $t = $s.ToLower()
    $t = $t.Replace([char]0x00E1, 'a').Replace([char]0x00E9, 'e').Replace([char]0x00ED, 'i')
    $t = $t.Replace([char]0x00F3, 'o').Replace([char]0x00FA, 'u').Replace([char]0x00FC, 'u')
    $t = $t.Replace([char]0x00F1, 'n')
    return $t
}

function Escapar-Xml($s) {
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

# PowerShell 5.1 escribe BOM con -Encoding UTF8, y javac no traga el BOM.
function Escribir-Utf8SinBom($ruta, $texto) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ruta, $texto, $enc)
}

# =====================================================================
#  1. Comprobar la entrada
# =====================================================================
Paso "Comprobando el HTML de entrada"
if (-not (Test-Path -LiteralPath $Html)) { Morir "no existe el archivo: $Html" }
$Html = (Resolve-Path -LiteralPath $Html).Path
if ([System.IO.Path]::GetExtension($Html).ToLower() -ne '.html') { Aviso "el archivo no termina en .html, se usara igual" }
$tamHtml = (Get-Item -LiteralPath $Html).Length
Ok "$Html  ($tamHtml bytes)"

$baseNombre = [System.IO.Path]::GetFileNameWithoutExtension($Html)
if (-not $Nombre) { $Nombre = $baseNombre }

$slug = (Quitar-Acentos $baseNombre).ToLower() -replace '[^a-z0-9]+', '-'
$slug = $slug.Trim('-')
if (-not $slug) { $slug = "app" }

if (-not $Package) {
    $seg = (Quitar-Acentos $baseNombre).ToLower() -replace '[^a-z0-9]', ''
    if (-not $seg) { $seg = "app" }
    if ($seg[0] -match '\d') { $seg = "app$seg" }
    $Package = "com.usuario.$seg"
}
if ($Package -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
    Morir "el identificador '$Package' no es valido (usa minusculas separadas por puntos, ej. com.yo.miapp)"
}
Ok "nombre visible : $Nombre"
Ok "identificador  : $Package"

# =====================================================================
#  2. Localizar el SDK, las build-tools y el JDK
# =====================================================================
Paso "Buscando las herramientas"

$Sdk = $null
foreach ($c in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT,
                 "$env:LOCALAPPDATA\Android\Sdk",
                 "$env:USERPROFILE\AppData\Local\Android\Sdk",
                 "C:\Android\Sdk")) {
    if ($c -and (Test-Path -LiteralPath (Join-Path $c 'platform-tools'))) { $Sdk = $c; break }
}
if (-not $Sdk) { Morir "no encuentro el SDK de Android. Define la variable ANDROID_HOME." }
Ok "SDK           : $Sdk"

$Bt = Get-ChildItem (Join-Path $Sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
      Where-Object { (Test-Path (Join-Path $_.FullName 'aapt2.exe')) -and (Test-Path (Join-Path $_.FullName 'd8.bat')) } |
      Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } |
      Select-Object -Last 1
if (-not $Bt) { Morir "no encuentro build-tools con aapt2 y d8 dentro del SDK." }
$Bt = $Bt.FullName
Ok "build-tools   : $(Split-Path $Bt -Leaf)"

$plat = Get-ChildItem (Join-Path $Sdk 'platforms') -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'android.jar') } |
        Sort-Object { [int]($_.Name -replace '[^0-9]', '') }
if (-not $plat) { Morir "no hay ninguna plataforma (android-XX) instalada en el SDK." }
$platElegida = $plat | Where-Object { [int]($_.Name -replace '[^0-9]','') -ge $TargetSdk } | Select-Object -First 1
if (-not $platElegida) {
    $platElegida = $plat | Select-Object -Last 1
    $TargetSdk = [int]($platElegida.Name -replace '[^0-9]', '')
    Aviso "no hay android-$($TargetSdk) instalado; se compila contra $($platElegida.Name)"
}
$Jar = Join-Path $platElegida.FullName 'android.jar'
Ok "android.jar   : $($platElegida.Name)"

$JavaHome = $null
foreach ($c in @($env:JAVA_HOME,
                 "$env:ProgramFiles\Android\Android Studio\jbr",
                 "$env:ProgramFiles\Eclipse Adoptium",
                 "$env:ProgramFiles\Java")) {
    if (-not $c -or -not (Test-Path -LiteralPath $c)) { continue }
    if (Test-Path (Join-Path $c 'bin\javac.exe')) { $JavaHome = $c; break }
    $sub = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.FullName 'bin\javac.exe') } | Select-Object -Last 1
    if ($sub) { $JavaHome = $sub.FullName; break }
}
if (-not $JavaHome) { Morir "no encuentro un JDK (javac). Define JAVA_HOME." }
$javac    = Join-Path $JavaHome 'bin\javac.exe'
$keytool  = Join-Path $JavaHome 'bin\keytool.exe'
Ok "JDK           : $JavaHome"

$javacMajor = 8
try {
    $v = (& $javac -version 2>&1) -join ''
    if ($v -match 'javac\s+(\d+)') { $javacMajor = [int]$Matches[1] }
} catch { }
Ok "javac         : version $javacMajor"

$aapt2     = Join-Path $Bt 'aapt2.exe'
$d8        = Join-Path $Bt 'd8.bat'
$zipalign  = Join-Path $Bt 'zipalign.exe'
$apksigner = Join-Path $Bt 'apksigner.bat'

# =====================================================================
#  3. Crear el proyecto Android
# =====================================================================
Paso "Generando el proyecto Android"

$work  = Join-Path $PSScriptRoot "_build\$slug"
$app   = Join-Path $work "app\src\main"
$res   = Join-Path $app "res"
$assets= Join-Path $app "assets"
$pkgDir= Join-Path $app ("java\" + $Package.Replace('.', '\'))
$bld   = Join-Path $work "out"

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
foreach ($d in @($pkgDir, $assets, "$res\values",
                 "$res\mipmap-mdpi", "$res\mipmap-hdpi", "$res\mipmap-xhdpi",
                 "$res\mipmap-xxhdpi", "$res\mipmap-xxxhdpi",
                 "$bld\gen", "$bld\classes", "$bld\dex")) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Copy-Item -LiteralPath $Html -Destination (Join-Path $assets "index.html") -Force
Ok "proyecto en $work"

# --- manifest ---
$manifestTpl = @'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="__PACKAGE__"
    android:versionCode="1"
    android:versionName="1.0">

    <uses-sdk android:minSdkVersion="__MINSDK__" android:targetSdkVersion="__TARGETSDK__" />

    <application
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:theme="@style/AppTheme"
        android:hardwareAccelerated="true"
        android:allowBackup="true"
        android:supportsRtl="false">

        <activity
            android:name="__PACKAGE__.MainActivity"
            android:label="@string/app_name"
            android:exported="true"
            android:launchMode="singleTask"
            android:screenOrientation="__ORIENTACION__"
            android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboardHidden|uiMode|density">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
'@
$manifest = $manifestTpl.Replace('__PACKAGE__', $Package).
                         Replace('__MINSDK__', $MinSdk).
                         Replace('__TARGETSDK__', $TargetSdk).
                         Replace('__ORIENTACION__', $Orientacion)
Escribir-Utf8SinBom (Join-Path $app 'AndroidManifest.xml') $manifest
# --- MainActivity.java ---
$javaTpl = @'
package __PACKAGE__;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/** Envoltorio nativo: carga el HTML de assets/index.html en un WebView a pantalla completa.
 *  Usa a proposito APIs obsoletas (FLAG_FULLSCREEN y setSystemUiVisibility): son el
 *  respaldo que funciona en ROMs que ignoran WindowInsetsController. */
@SuppressWarnings("deprecation")
public class MainActivity extends Activity {

    private static final String TAG = "WebApp";
    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);

        web = new WebView(this);
        web.setBackgroundColor(0xFF008080);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        web.setHorizontalScrollBarEnabled(false);
        web.setVerticalScrollBarEnabled(false);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            s.setSafeBrowsingEnabled(false);
        }

        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient());

        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");

        // Las barras se ocultan en onResume/onWindowFocusChanged, cuando el DecorView
        // ya existe: hacerlo antes lanza NullPointerException en algunas ROMs.
    }

    // setSystemUiVisibility esta obsoleto, pero es el respaldo que funciona en ROMs
    // que ignoran WindowInsetsController. Se usa a proposito.
    @SuppressWarnings("deprecation")
    private void goFullscreen() {
        Window w = getWindow();
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                w.setDecorFitsSystemWindows(false);
                WindowInsetsController c = w.getInsetsController();
                if (c != null) {
                    c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                    c.setSystemBarsBehavior(
                            WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "WindowInsetsController: " + t);
        }
        try {
            w.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
            w.getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                  | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                  | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                  | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                  | View.SYSTEM_UI_FLAG_FULLSCREEN
                  | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        } catch (Throwable t) {
            Log.w(TAG, "systemUiVisibility: " + t);
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) goFullscreen();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
        goFullscreen();
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (web != null) web.onPause();
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.loadUrl("about:blank");
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }

}
'@
$java = $javaTpl.Replace('__PACKAGE__', $Package)
Escribir-Utf8SinBom (Join-Path $pkgDir 'MainActivity.java') $java

# --- recursos ---
$strings = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">$(Escapar-Xml $Nombre)</string>
</resources>
"@
Escribir-Utf8SinBom (Join-Path $res 'values\strings.xml') $strings

$styles = @'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="@android:style/Theme.Material.NoActionBar.Fullscreen">
        <item name="android:windowBackground">#FF008080</item>
        <item name="android:colorBackground">#FF008080</item>
        <item name="android:windowContentOverlay">@null</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
</resources>
'@
Escribir-Utf8SinBom (Join-Path $res 'values\styles.xml') $styles
Ok "manifest, MainActivity y recursos"

# --- iconos ---
$densidades = @('mipmap-mdpi','mipmap-hdpi','mipmap-xhdpi','mipmap-xxhdpi','mipmap-xxxhdpi')
if ($Icono) {
    if (-not (Test-Path -LiteralPath $Icono)) { Morir "no existe el icono: $Icono" }
    $png = (Resolve-Path -LiteralPath $Icono).Path
    foreach ($d in $densidades) { Copy-Item $png (Join-Path $res "$d\ic_launcher.png") -Force }
    Ok "icono propio -> las 5 densidades"
} else {
    # Icono generico estilo Windows 95, embebido en base64 para no depender de nada externo
    $b64 = 'iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAYAAABS3GwHAAAB70lEQVR42u3dQQqDMBBA0bH0YOZkxpslJ5ueIYKSmvfWLUjkM5shbpmZAYv6OAIEAAIAAYAAQAAgABAACAAEAAKA9/iO/qH37tSYVq3VBAABgABAACAAEAAIAAQAAgABIAAIu0D32PfdKXNZa80EAAGAAEAAIAAQAAgABAACAAGAACDm2AWK8YtdvJV49cU9JgAIAAQAAgABgABAACAAEAAIAAQAAgABgABAACAAEAAIAAQAAgABgABAACAAEAAIAAQAAgABIAAQAAgABAACAAFA+EbY2vI4hn6/nedSz2MCgABAACAAEAAIAAQAAgABgABAABB2gcJuzxWjz2N3yAQAAYAAQAAgABAACAABgABAACAAEAAIAAQAAgABgABAACAAEAAIAAQAAoBwL9DE/v1eHff8mAAgABAACAAEAAIAAYAAQAAgABAAhF2geGJ3aLXnMQFAACAAEAAIAAQAAgABgABAACAAEAAIAAQAAgABgABAACAAEAAIAAQAAgABgABAACAAEAAIAAQAAgABgABAACAAiPm/EVart4IJAAIAAYAAQAAgABAACAAEAAIAAUDMtwvUWnPKmAAgABAACAAEAAIAAYAAQAAgABAA3G/LzBz5QynFqWECgABAACAAEAAIAAQAAgABgABAADCfH4gDLFtRLSRKAAAAAElFTkSuQmCC'
    $bytes = [System.Convert]::FromBase64String($b64)
    foreach ($d in $densidades) {
        [System.IO.File]::WriteAllBytes((Join-Path $res "$d\ic_launcher.png"), $bytes)
    }
    Ok "icono generico -> las 5 densidades"
}

# =====================================================================
#  4. Compilar
# =====================================================================
Paso "Compilando con aapt2 + javac + d8"

& $aapt2 compile --dir $res -o "$bld\res.zip"
if ($LASTEXITCODE -ne 0) { Morir "aapt2 compile fallo" }
Ok "recursos compilados"

& $aapt2 link -o "$bld\base.apk" -I $Jar --manifest (Join-Path $app 'AndroidManifest.xml') `
    -R "$bld\res.zip" --java "$bld\gen" -A $assets --auto-add-overlay
if ($LASTEXITCODE -ne 0) { Morir "aapt2 link fallo" }
Ok "recursos enlazados + assets dentro del APK"

$fuentes = @(Get-ChildItem -Path (Join-Path $app 'java') -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$fuentes += (Join-Path $bld "gen\$($Package.Replace('.', '\'))\R.java")
if ($javacMajor -ge 12) {
    & $javac -encoding UTF-8 --release 11 -nowarn -Xlint:-deprecation -classpath $Jar -d "$bld\classes" @fuentes
} else {
    & $javac -encoding UTF-8 -source 8 -target 8 -nowarn -Xlint:-deprecation -bootclasspath $Jar -d "$bld\classes" @fuentes
}
if ($LASTEXITCODE -ne 0) { Morir "javac fallo" }
Ok "codigo Java compilado"

$clases = @(Get-ChildItem "$bld\classes" -Recurse -Filter *.class | ForEach-Object { $_.FullName })
& $d8 --lib $Jar --min-api $MinSdk --output "$bld\dex" @clases
if ($LASTEXITCODE -ne 0) { Morir "d8 fallo (si aparece un NullPointerException interno, mira si hay clases anonimas en el Java)" }
Ok "classes.dex generado"

Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
$zip = [System.IO.Compression.ZipFile]::Open("$bld\base.apk", 'Update')
try {
    $e = $zip.GetEntry("classes.dex")
    if ($e) { $e.Delete() }
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, "$bld\dex\classes.dex", "classes.dex",
        [System.IO.Compression.CompressionLevel]::Optimal)
} finally { $zip.Dispose() }
Ok "classes.dex empaquetado"

& $zipalign -p -f 4 "$bld\base.apk" "$bld\aligned.apk"
if ($LASTEXITCODE -ne 0) { Morir "zipalign fallo" }
Ok "APK alineado"

# --- firma (keystore de desarrollo compartido) ---
$ks = Join-Path $PSScriptRoot 'dev.keystore'
if (-not (Test-Path $ks)) {
    Write-Host "  creando keystore de desarrollo..."
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'     # keytool escribe en stderr y no es un error
    & $keytool -genkeypair -v -keystore $ks -storetype PKCS12 `
        -storepass android -keypass android -alias dev `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Desarrollo Android, OU=Dev, C=ES" | Out-Null
    $kc = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($kc -ne 0) { Morir "keytool fallo" }
}
if (-not $Salida) { $Salida = Join-Path $PSScriptRoot 'dist' }
New-Item -ItemType Directory -Force -Path $Salida | Out-Null
$apk = Join-Path $Salida "$slug.apk"
Remove-Item $apk -ErrorAction SilentlyContinue
& $apksigner sign --ks $ks --ks-pass pass:android --key-pass pass:android --ks-key-alias dev `
    --out $apk "$bld\aligned.apk"
if ($LASTEXITCODE -ne 0) { Morir "la firma fallo" }
Ok "APK firmado"

# =====================================================================
#  5. Verificar y resumir
# =====================================================================
Paso "Verificacion"
$firma = & $apksigner verify $apk 2>&1
if ($LASTEXITCODE -ne 0) { Morir "la firma no verifica`n$firma" }
Ok "firma valida (v2/v3)"

$badging = & $aapt2 dump badging $apk
$pkgLine = ($badging | Select-String "^package:").Line
$lblLine = ($badging | Select-String "application-label:").Line
if ($pkgLine) { Ok $pkgLine.Trim() }
if ($lblLine) { Ok $lblLine.Trim() }

$tam = (Get-Item $apk).Length
Write-Host ""
Write-Host ("  APK: $apk") -ForegroundColor Yellow
Write-Host ("       {0:N0} bytes ({1:N0} KB)" -f $tam, ($tam / 1KB)) -ForegroundColor Yellow
Write-Host ""

if ($Instalar) {
    Paso "Instalando en el movil"
    $adb = Join-Path $Sdk 'platform-tools\adb.exe'
    $devs = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
    if ($devs.Count -eq 0) { Morir "no hay ningun movil autorizado conectado por USB" }
    if ($devs.Count -gt 1) { Morir "hay varios dispositivos conectados, desconecta los que sobren" }
    $serial = ($devs[0] -split '\s+')[0]
    & $adb -s $serial install -r $apk
    if ($LASTEXITCODE -ne 0) { Morir "adb install fallo" }
    Ok "instalado en $serial"
    Write-Host "  abrelo desde el cajon de aplicaciones del movil" -ForegroundColor Yellow
}

# Patches the `desktop_webview_window` plugin so that it builds on Windows arm64.
#
# The plugin version we depend on (0.3.2) bundles the WebView2 SDK loader for
# x64 only, which makes the arm64 build fail at link time with:
#
#   Webview2Loader.dll.lib : warning LNK4272: library machine type 'x64'
#   conflicts with target machine type 'ARM64'
#   ... fatal error LNK1120: 3 unresolved externals
#
# The official Microsoft.Web.WebView2 NuGet package ships the same loader for
# arm64, so we download it, drop the arm64 files next to the bundled x64 ones
# and point the plugin's CMakeLists.txt at the arm64 directory.
#
# Run this after `flutter pub get` (so the plugin is in the pub cache) and
# before `flutter build windows`.

$ErrorActionPreference = "Stop"

$WebView2Version = "1.0.4258.31"
$WebView2Url = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$WebView2Version/microsoft.web.webview2.$WebView2Version.nupkg"

# Locate the plugin in the pub cache via the generated package config.
$packageConfigPath = ".dart_tool/package_config.json"
if (-not (Test-Path $packageConfigPath)) {
    throw "$packageConfigPath not found. Run 'flutter pub get' first."
}
$packageConfig = Get-Content $packageConfigPath -Raw | ConvertFrom-Json
$package = $packageConfig.packages | Where-Object { $_.name -eq "desktop_webview_window" }
if (-not $package) {
    throw "desktop_webview_window not found in $packageConfigPath."
}
$pluginDir = ([System.Uri]$package.rootUri).LocalPath
$pluginWindowsDir = Join-Path $pluginDir "windows"
Write-Host "Patching $pluginWindowsDir"

# Download and extract the WebView2 SDK.
$tempDir = Join-Path $env:RUNNER_TEMP "webview2-$WebView2Version"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$zipPath = Join-Path $tempDir "webview2.zip"
Write-Host "Downloading $WebView2Url"
Invoke-WebRequest -Uri $WebView2Url -OutFile $zipPath
Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

# Copy the arm64 loader next to the bundled x64 one.
$sourceDir = Join-Path $tempDir "build/native/arm64"
$destDir = Join-Path $pluginWindowsDir "libs/arm64"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
foreach ($file in @("WebView2Loader.dll", "WebView2Loader.dll.lib")) {
    Copy-Item (Join-Path $sourceDir $file) (Join-Path $destDir $file) -Force
    Write-Host "Copied $file"
}

# Point the plugin at the arm64 loader.
$cmakeListsPath = Join-Path $pluginWindowsDir "CMakeLists.txt"
$cmakeLists = Get-Content $cmakeListsPath -Raw
$patched = $cmakeLists -replace "/libs/x64/", "/libs/arm64/"
if ($patched -eq $cmakeLists) {
    throw "No '/libs/x64/' references found in $cmakeListsPath."
}
Set-Content -Path $cmakeListsPath -Value $patched -NoNewline
Write-Host "Updated $cmakeListsPath"

Write-Host "Done."

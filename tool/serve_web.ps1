param(
  [switch]$Build,
  [ValidateSet('127.0.0.1','localhost','0.0.0.0')]
  [string]$Hostname = '127.0.0.1',
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'

$projRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $projRoot

if ($Build) {
  Write-Host "Building web release without PWA SW..." -ForegroundColor Yellow
  flutter build web --release --pwa-strategy=none | Out-Host
}

$root = Join-Path (Get-Location) 'build/web'
if (!(Test-Path $root)) {
  throw "Folder not found: $root. Run with -Build to generate it."
}

Add-Type -AssemblyName System.Net.HttpListener
$prefix = "http://$Hostname:$Port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Serving $root at $prefix (Ctrl+C to stop)" -ForegroundColor Green

$mime = @{ 
  '.html'='text/html'; '.js'='application/javascript'; '.mjs'='application/javascript';
  '.css'='text/css'; '.json'='application/json'; '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg';
  '.svg'='image/svg+xml'; '.ico'='image/x-icon'; '.wasm'='application/wasm'; '.map'='application/json';
  '.ttf'='font/ttf'; '.otf'='font/otf'; '.woff'='font/woff'; '.woff2'='font/woff2'
}

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    Start-Job -ArgumentList @($ctx,$root,$mime) -ScriptBlock {
      param($ctx,$root,$mime)
      try {
        $path = $ctx.Request.Url.AbsolutePath.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($path)) { $path = 'index.html' }
        $full = Join-Path $root $path

        if (!(Test-Path $full)) {
          # SPA fallback to index.html for navigation requests
          if ($ctx.Request.HttpMethod -eq 'GET' -and $ctx.Request.Headers['Accept'] -like '*text/html*') {
            $full = Join-Path $root 'index.html'
          }
        }

        if (Test-Path $full) {
          $ext = [System.IO.Path]::GetExtension($full).ToLower()
          $ctype = $mime[$ext]
          if (-not $ctype) { $ctype = 'application/octet-stream' }
          $bytes = [System.IO.File]::ReadAllBytes($full)
          $ctx.Response.StatusCode = 200
          $ctx.Response.Headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
          $ctx.Response.Headers['Pragma'] = 'no-cache'
          $ctx.Response.Headers['Expires'] = '0'
          $ctx.Response.ContentType = $ctype
          $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
          $ctx.Response.StatusCode = 404
          $msg = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
          $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
        }
      } catch {
        try { $ctx.Response.StatusCode = 500 } catch {}
      } finally {
        try { $ctx.Response.OutputStream.Close() } catch {}
      }
    } | Out-Null
  }
} finally {
  $listener.Stop()
  $listener.Close()
}


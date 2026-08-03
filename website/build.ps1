[CmdletBinding()]
param(
    [ValidatePattern('^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$RepositoryUrl = ''
)

$ErrorActionPreference = 'Stop'

$siteRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$distRoot = [IO.Path]::GetFullPath((Join-Path $siteRoot 'dist'))
$expectedPrefix = $siteRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $distRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to build outside the website directory: $distRoot"
}

$required = @('index.html', 'styles.css', 'app.js')
foreach ($name in $required) {
    $path = Join-Path $siteRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required website file is missing: $name"
    }
}

if (Test-Path -LiteralPath $distRoot) {
    Remove-Item -LiteralPath $distRoot -Recurse -Force
}

$serverRoot = Join-Path $distRoot 'server'
$staticRoot = Join-Path $distRoot 'static'
New-Item -ItemType Directory -Path $serverRoot, $staticRoot -Force | Out-Null

$index = [IO.File]::ReadAllText((Join-Path $siteRoot 'index.html'))
if ($RepositoryUrl) {
    $index = $index.Replace('__REPO_URL__', $RepositoryUrl)
}
$styles = [IO.File]::ReadAllText((Join-Path $siteRoot 'styles.css'))
$script = [IO.File]::ReadAllText((Join-Path $siteRoot 'app.js'))
$indexJson = ConvertTo-Json -InputObject $index -Compress
$stylesJson = ConvertTo-Json -InputObject $styles -Compress
$scriptJson = ConvertTo-Json -InputObject $script -Compress

$ogPath = Join-Path $siteRoot 'og.png'
$ogBase64 = if (Test-Path -LiteralPath $ogPath -PathType Leaf) {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($ogPath))
} else {
    ''
}
$ogJson = ConvertTo-Json -InputObject $ogBase64 -Compress

$worker = @"
const INDEX = $indexJson;
const STYLES = $stylesJson;
const SCRIPT = $scriptJson;
const OG_BASE64 = $ogJson;

const headers = {
  "content-security-policy": "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "referrer-policy": "strict-origin-when-cross-origin",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY"
};

function response(body, contentType, cacheControl = "public, max-age=300") {
  return new Response(body, {
    headers: { ...headers, "content-type": contentType, "cache-control": cacheControl }
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (path === "/" || path === "/index.html") {
      const html = INDEX.replaceAll("__SITE_ORIGIN__", url.origin);
      return response(html, "text/html; charset=utf-8", "public, max-age=60");
    }
    if (path === "/styles.css") return response(STYLES, "text/css; charset=utf-8");
    if (path === "/app.js") return response(SCRIPT, "text/javascript; charset=utf-8");
    if (path === "/og.png" && OG_BASE64) {
      const bytes = Uint8Array.from(atob(OG_BASE64), (character) => character.charCodeAt(0));
      return response(bytes, "image/png", "public, max-age=86400");
    }
    return new Response("Not found", {
      status: 404,
      headers: { ...headers, "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" }
    });
  }
};
"@

$workerPath = Join-Path $serverRoot 'index.js'
[IO.File]::WriteAllText($workerPath, $worker, [Text.UTF8Encoding]::new($false))

[IO.File]::WriteAllText((Join-Path $staticRoot 'index.html'), $index, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $siteRoot 'styles.css'), (Join-Path $siteRoot 'app.js') -Destination $staticRoot
if (Test-Path -LiteralPath $ogPath -PathType Leaf) {
    Copy-Item -LiteralPath $ogPath -Destination $staticRoot
}

Write-Host "Website build ready: $distRoot"

# tiny static file server for previewing the game (http://localhost:8765/)
$root = Split-Path -Parent $PSScriptRoot
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add('http://localhost:8765/')
$l.Start()
Write-Host "serving $root on http://localhost:8765/"
$types = @{ '.html'='text/html'; '.png'='image/png'; '.webp'='image/webp'; '.js'='text/javascript'; '.json'='application/json'; '.css'='text/css' }
while ($l.IsListening) {
  $ctx = $l.GetContext()
  $p = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
  # dev only: PUT /art/<name>.png saves the body into art/ (used to write shrunk art from the browser)
  if ($ctx.Request.HttpMethod -eq 'PUT' -and $p -match '^art/[A-Za-z0-9_-]+\.png$') {
    $ms = New-Object IO.MemoryStream; $ctx.Request.InputStream.CopyTo($ms)
    [IO.File]::WriteAllBytes((Join-Path $root $p), $ms.ToArray())
    $ctx.Response.StatusCode = 204; $ctx.Response.Close(); continue
  }
  if (-not $p) { $p = 'Smashed.html' }
  $f = Join-Path $root $p
  if (Test-Path $f -PathType Leaf) {
    $b = [IO.File]::ReadAllBytes($f)
    $ext = [IO.Path]::GetExtension($f).ToLower()
    $ctx.Response.ContentType = if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' }
    $ctx.Response.OutputStream.Write($b, 0, $b.Length)
  } else { $ctx.Response.StatusCode = 404 }
  $ctx.Response.Close()
}

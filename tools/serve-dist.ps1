param(
  [switch]$NoBrowser,
  [int]$StartPort = 8099
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SiteRoot = $ProjectRoot
$IndexFile = Join-Path $SiteRoot "html\index.html"

if (-not (Test-Path -LiteralPath $IndexFile)) {
  Write-Host ""
  Write-Host "没有找到 html\index.html。请先生成一次打包文件：" -ForegroundColor Yellow
  Write-Host "  请先确认最终版文件已整理完整"
  Write-Host ""
  Write-Host "整理完成后再双击 启动网站.bat。"
  Read-Host "按 Enter 退出"
  exit 1
}

function Get-MimeType {
  param([string]$Path)

  switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8"; break }
    ".css" { "text/css; charset=utf-8"; break }
    ".js" { "text/javascript; charset=utf-8"; break }
    ".json" { "application/json; charset=utf-8"; break }
    ".svg" { "image/svg+xml"; break }
    ".png" { "image/png"; break }
    ".jpg" { "image/jpeg"; break }
    ".jpeg" { "image/jpeg"; break }
    ".webp" { "image/webp"; break }
    ".gif" { "image/gif"; break }
    ".ico" { "image/x-icon"; break }
    ".mp4" { "video/mp4"; break }
    ".mp3" { "audio/mpeg"; break }
    ".wav" { "audio/wav"; break }
    ".woff" { "font/woff"; break }
    ".woff2" { "font/woff2"; break }
    default { "application/octet-stream"; break }
  }
}

function Get-FreePort {
  param([int]$StartPort = 8099)

  for ($port = $StartPort; $port -lt ($StartPort + 100); $port++) {
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $port)
    try {
      $probe.Start()
      return $port
    } catch {
      continue
    } finally {
      $probe.Stop()
    }
  }

  throw "没有找到可用端口。"
}

function Get-LanAddress {
  $addresses = [Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName()) |
    Where-Object {
      $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
      -not $_.IPAddressToString.StartsWith("127.") -and
      -not $_.IPAddressToString.StartsWith("169.254.")
    }

  if ($addresses) {
    return $addresses[0].IPAddressToString
  }

  return $null
}

function Write-HttpResponse {
  param(
    [IO.Stream]$Stream,
    [int]$StatusCode,
    [string]$StatusText,
    [hashtable]$Headers,
    [byte[]]$Body,
    [int]$Offset = 0,
    [int]$Count = -1
  )

  if ($Count -lt 0) {
    $Count = $Body.Length
  }

  $headerText = "HTTP/1.1 $StatusCode $StatusText`r`n"
  foreach ($key in $Headers.Keys) {
    $headerText += "$key`: $($Headers[$key])`r`n"
  }
  $headerText += "Connection: close`r`n`r`n"

  $headerBytes = [Text.Encoding]::ASCII.GetBytes($headerText)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)

  if ($Body.Length -gt 0 -and $Count -gt 0) {
    $Stream.Write($Body, $Offset, $Count)
  }
}

function Send-Text {
  param(
    [IO.Stream]$Stream,
    [int]$StatusCode,
    [string]$StatusText,
    [string]$Message
  )

  $body = [Text.Encoding]::UTF8.GetBytes($Message)
  Write-HttpResponse $Stream $StatusCode $StatusText @{
    "Content-Type" = "text/plain; charset=utf-8"
    "Content-Length" = $body.Length
  } $body
}

function Send-File {
  param(
    [IO.Stream]$Stream,
    [string]$Path,
    [string]$RangeHeader
  )

  $bytes = [IO.File]::ReadAllBytes($Path)
  $length = $bytes.Length
  $headers = @{
    "Content-Type" = Get-MimeType $Path
    "Accept-Ranges" = "bytes"
  }

  if ($RangeHeader -match "^bytes=(\d*)-(\d*)$") {
    $start = if ($Matches[1] -ne "") { [int64]$Matches[1] } else { 0 }
    $end = if ($Matches[2] -ne "") { [int64]$Matches[2] } else { $length - 1 }
    $end = [Math]::Min($end, $length - 1)

    if ($start -ge 0 -and $start -le $end -and $end -lt $length) {
      $count = [int]($end - $start + 1)
      $headers["Content-Range"] = "bytes $start-$end/$length"
      $headers["Content-Length"] = $count
      Write-HttpResponse $Stream 206 "Partial Content" $headers $bytes ([int]$start) $count
      return
    }
  }

  $headers["Content-Length"] = $length
  Write-HttpResponse $Stream 200 "OK" $headers $bytes
}

function Resolve-RequestPath {
  param(
    [string]$UrlPath,
    [string]$RootPath
  )

  $cleanPath = $UrlPath.Split("?")[0].TrimStart("/")
  if ([string]::IsNullOrWhiteSpace($cleanPath)) {
    $cleanPath = "html/index.html"
  }

  $cleanPath = [Uri]::UnescapeDataString($cleanPath).Replace("/", [IO.Path]::DirectorySeparatorChar)
  $fullPath = [IO.Path]::GetFullPath((Join-Path $RootPath $cleanPath))
  $rootFullPath = [IO.Path]::GetFullPath($RootPath)

  if (-not $fullPath.StartsWith($rootFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }

  if ((Test-Path -LiteralPath $fullPath -PathType Container)) {
    $fullPath = Join-Path $fullPath "index.html"
  }

  return $fullPath
}

$port = Get-FreePort -StartPort $StartPort
$localUrl = "http://127.0.0.1:$port/html/index.html"
$lanAddress = Get-LanAddress
$lanUrl = if ($lanAddress) { "http://$lanAddress`:$port/html/index.html" } else { "" }
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $port)
$listener.Start()

Write-Host ""
Write-Host "Maison Noire 网站已启动：" -ForegroundColor Green
Write-Host "  电脑访问：$localUrl"
if ($lanUrl) {
  Write-Host "  手机访问：$lanUrl" -ForegroundColor Cyan
  Write-Host "  手机和电脑需要连接同一个 Wi-Fi；如果 Windows 防火墙提示，请允许专用网络访问。"
} else {
  Write-Host "  未检测到局域网 IP，手机暂时无法访问。"
}
Write-Host ""
Write-Host "关闭这个窗口即可停止网站。"
Write-Host ""

if (-not $NoBrowser) {
  Start-Process $localUrl
}

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 8192, $true)
      $requestLine = $reader.ReadLine()

      if ([string]::IsNullOrWhiteSpace($requestLine)) {
        Send-Text $stream 400 "Bad Request" "Bad Request"
        continue
      }

      $parts = $requestLine.Split(" ")
      if ($parts.Length -lt 2 -or $parts[0] -ne "GET") {
        Send-Text $stream 405 "Method Not Allowed" "Method Not Allowed"
        continue
      }

      $headers = @{}
      while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq "") {
          break
        }

        $separator = $line.IndexOf(":")
        if ($separator -gt 0) {
          $name = $line.Substring(0, $separator).Trim()
          $value = $line.Substring($separator + 1).Trim()
          $headers[$name] = $value
        }
      }

      $filePath = Resolve-RequestPath $parts[1] $SiteRoot
      if ($null -eq $filePath) {
        Send-Text $stream 403 "Forbidden" "Forbidden"
        continue
      }

      if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Send-Text $stream 404 "Not Found" "Not Found"
        continue
      }

      Send-File $stream $filePath $headers["Range"]
    } catch {
      try {
        Send-Text $stream 500 "Internal Server Error" "Internal Server Error"
      } catch {
        # The browser may have closed the connection already.
      }
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}



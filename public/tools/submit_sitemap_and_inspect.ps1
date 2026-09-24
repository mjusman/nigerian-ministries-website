<#
PowerShell helper: submit sitemap and run URL Inspection via Search Console API.

Usage (recommended):
1. Create OAuth credentials and a refresh token (instructions below or in README).
2. Store your credentials in a local file (not committed) e.g. C:\Users\<you>\.gcloud_creds\searchconsole.json with keys: client_id, client_secret, refresh_token
3. Run from PowerShell:
   PS> $creds = Get-Content -Raw -Path 'C:\Users\<you>\.gcloud_creds\searchconsole.json' | ConvertFrom-Json
   PS> & .\tools\submit_sitemap_and_inspect.ps1 -ClientId $creds.client_id -ClientSecret $creds.client_secret -RefreshToken $creds.refresh_token -SiteUrl 'https://nigerian-info.web.app' -SitemapUrl 'https://nigerian-info.web.app/sitemap.xml' -InspectUrls @('https://nigerian-info.web.app/', 'https://nigerian-info.web.app/articles/how-ministries-shape-national-policy.html')

Notes:
- The account used to generate the refresh token must have access to the Search Console property for your site.
- This script performs:
  1) Exchanges refresh token for an access token
  2) Submits the sitemap using the Webmasters API
  3) Calls the URL Inspection API for each specified URL and writes JSON responses to disk

#>
param(
  [Parameter(Mandatory=$true)] [string] $ClientId,
  [Parameter(Mandatory=$true)] [string] $ClientSecret,
  [Parameter(Mandatory=$true)] [string] $RefreshToken,
  [Parameter(Mandatory=$true)] [string] $SiteUrl,
  [Parameter(Mandatory=$true)] [string] $SitemapUrl,
  [Parameter(Mandatory=$false)] [string[]] $InspectUrls = @()
)

function Get-AccessToken {
  param($clientId, $clientSecret, $refreshToken)
  $body = @{
    client_id = $clientId
    client_secret = $clientSecret
    refresh_token = $refreshToken
    grant_type = 'refresh_token'
  }
  $resp = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body $body -ErrorAction Stop
  return $resp.access_token
}

function Submit-Sitemap {
  param($accessToken, $siteUrl, $sitemapUrl)
  $siteEnc = [System.Uri]::EscapeDataString($siteUrl)
  $uri = "https://www.googleapis.com/webmasters/v3/sites/$siteEnc/sitemaps?url=$([System.Uri]::EscapeDataString($sitemapUrl))"
  try {
    $r = Invoke-RestMethod -Method Post -Uri $uri -Headers @{ Authorization = "Bearer $accessToken" } -ErrorAction Stop
    Write-Output "Sitemap submitted successfully. Response:`n$r"
  } catch {
    Write-Output "Sitemap submission failed: $($_.Exception.Message)"
    if ($_.Exception.Response) {
      $txt = $_.Exception.Response.GetResponseStream()
      $sr = New-Object System.IO.StreamReader($txt)
      Write-Output $sr.ReadToEnd()
    }
  }
}

function Inspect-Url {
  param($accessToken, $siteUrl, $url, $outDir)
  $uri = 'https://searchconsole.googleapis.com/v1/urlInspection/index:inspect'
  $body = @{ inspectionUrl = $url; siteUrl = $siteUrl } | ConvertTo-Json -Depth 5
  try {
    $r = Invoke-RestMethod -Method Post -Uri $uri -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $body -ErrorAction Stop
    $json = $r | ConvertTo-Json -Depth 10
    $safeName = [System.IO.Path]::GetFileName([uri]$url).Replace('?', '_').Replace('&','_')
    $filename = Join-Path $outDir ("inspect-$(Get-Date -Format yyyyMMdd-HHmmss)-$safeName.json")
    $json | Out-File -FilePath $filename -Encoding utf8
    Write-Output "Inspection saved to $filename"
  } catch {
    Write-Output "Inspection failed for ${url}: $($_.Exception.Message)"
    if ($_.Exception.Response) {
      $txt = $_.Exception.Response.GetResponseStream()
      $sr = New-Object System.IO.StreamReader($txt)
      Write-Output $sr.ReadToEnd()
    }
  }
}

Write-Output "Exchanging refresh token for access token..."
$accessToken = Get-AccessToken -clientId $ClientId -clientSecret $ClientSecret -refreshToken $RefreshToken
Write-Output "Access token acquired. Submitting sitemap..."
Submit-Sitemap -accessToken $accessToken -siteUrl $SiteUrl -sitemapUrl $SitemapUrl

if ($InspectUrls.Count -gt 0) {
  $outDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\logs' | Resolve-Path -Relative
  $outDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\logs'
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  foreach ($u in $InspectUrls) {
    Write-Output "Inspecting: $u"
    Inspect-Url -accessToken $accessToken -siteUrl $SiteUrl -url $u -outDir $outDir
  }
}

Write-Output "Done. Review logs in the logs folder."
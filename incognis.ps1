# incognis.ps1 - main
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogFile = Join-Path $ScriptDir "incognis.log"
$BackupDir = Join-Path $ScriptDir "backups"
New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null

function Log($msg) {
  $t = Get-Date -Format u
  "$t`t$msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

function Write-ProgressStep($activity, $status, $percent) {
  Write-Progress -Activity $activity -Status $status -PercentComplete $percent
}

function Get-InstalledBrowsers {
  Write-ProgressStep "Scanning" "Detecting browsers" 10
  $candidates = @()

  # Chrome
  $chromePath = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\History"
  if (Test-Path $chromePath) {
    $candidates += [PSCustomObject]@{Name='Google Chrome'; Type='Chromium'; HistoryPath=$chromePath; Profile='Default'}
  }
  # Edge
  $edgePath = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\History"
  if (Test-Path $edgePath) {
    $candidates += [PSCustomObject]@{Name='Microsoft Edge'; Type='Chromium'; HistoryPath=$edgePath; Profile='Default'}
  }
  # Brave
  $bravePath = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\Default\History"
  if (Test-Path $bravePath) {
    $candidates += [PSCustomObject]@{Name='Brave'; Type='Chromium'; HistoryPath=$bravePath; Profile='Default'}
  }
  # Opera
  $operaPath = Join-Path $env:APPDATA "Opera Software\Opera Stable\History"
  if (Test-Path $operaPath) {
    $candidates += [PSCustomObject]@{Name='Opera'; Type='Chromium'; HistoryPath=$operaPath; Profile='Stable'}
  }
  # Vivaldi
  $vivaldiPath = Join-Path $env:LOCALAPPDATA "Vivaldi\User Data\Default\History"
  if (Test-Path $vivaldiPath) {
    $candidates += [PSCustomObject]@{Name='Vivaldi'; Type='Chromium'; HistoryPath=$vivaldiPath; Profile='Default'}
  }
  # Chromium
  $chromiumPath = Join-Path $env:LOCALAPPDATA "Chromium\User Data\Default\History"
  if (Test-Path $chromiumPath) {
    $candidates += [PSCustomObject]@{Name='Chromium'; Type='Chromium'; HistoryPath=$chromiumPath; Profile='Default'}
  }
  # Firefox (scan profiles)
  $ffProfilesIni = Join-Path $env:APPDATA "Mozilla\Firefox\profiles.ini"
  if (Test-Path $ffProfilesIni) {
    $profiles = Select-String -Path $ffProfilesIni -Pattern '^Path=' | ForEach-Object { $_.Line.Split('=')[1] }
    foreach ($profile in $profiles) {
      $ffHistory = Join-Path $env:APPDATA "Mozilla\Firefox\$profile\places.sqlite"
      if (Test-Path $ffHistory) {
        $candidates += [PSCustomObject]@{Name='Firefox'; Type='Firefox'; HistoryPath=$ffHistory; Profile=$profile}
      }
    }
  }
  Write-ProgressStep "Scanning" "Detection complete" 100
  return $candidates
}

# Main interactive loop
while ($true) {
  Clear-Host
  Write-Host "Incognis — Browser History Cleaner"
  Write-Host "1) Scan for browsers"
  Write-Host "2) Preview history"
  Write-Host "3) Clean history"
  Write-Host "4) Dry run"
  Write-Host "5) Quit"
  $choice = Read-Host "Choose an option (1-5)"
  switch ($choice) {
    '1' {
      $browsers = Get-InstalledBrowsers
      $browsers | Format-Table -AutoSize
      Read-Host "Press Enter to continue"
    }
    '2' {
      $browsers = Get-InstalledBrowsers
      Write-Host "Select browser to preview:"
      for ($i=0; $i -lt $browsers.Count; $i++) {
        Write-Host "$i) $($browsers[$i].Name) [$($browsers[$i].Profile)]"
      }
      $idx = Read-Host "Enter browser number"
      if ($idx -match '^\d+$' -and $idx -lt $browsers.Count) {
        $browser = $browsers[$idx]
        $dbPath = $browser.HistoryPath
        $copyPath = Copy-DbSafely $dbPath $BackupDir
        Log "Copied $dbPath to $copyPath for preview"
        $page = 0
        $pageSize = 20
        while ($true) {
          if ($browser.Type -eq 'Chromium') {
            $offset = $page * $pageSize
            $sql = "SELECT urls.url, urls.title, urls.visit_count, visits.visit_time FROM urls JOIN visits ON urls.id = visits.url ORDER BY visits.visit_time DESC LIMIT $pageSize OFFSET $offset;"
            $results = Query-Sqlite $copyPath $sql
            Write-Host $results
          } elseif ($browser.Type -eq 'Firefox') {
            $offset = $page * $pageSize
            $sql = "SELECT p.url, p.title, p.visit_count, v.visit_date FROM moz_places p JOIN moz_historyvisits v ON p.id = v.place_id ORDER BY v.visit_date DESC LIMIT $pageSize OFFSET $offset;"
            $results = Query-Sqlite $copyPath $sql
            Write-Host $results
          } else {
            Write-Host "Preview not supported for this browser."
            break
          }
          $nav = Read-Host "Enter N for next page, P for previous, Q to quit"
          if ($nav -eq 'N') { $page++ }
          elseif ($nav -eq 'P' -and $page -gt 0) { $page-- }
          elseif ($nav -eq 'Q') { break }
        }
      } else {
        Write-Host "Invalid selection."
        Read-Host "Press Enter"
      }
    }
    '3' {
      $browsers = Get-InstalledBrowsers
      Write-Host "Select browser to clean:"
      for ($i=0; $i -lt $browsers.Count; $i++) {
        Write-Host "$i) $($browsers[$i].Name) [$($browsers[$i].Profile)]"
      }
      $idx = Read-Host "Enter browser number"
      if ($idx -match '^\d+$' -and $idx -lt $browsers.Count) {
        $browser = $browsers[$idx]
        $dbPath = $browser.HistoryPath
        $copyPath = Copy-DbSafely $dbPath $BackupDir
        Log "Backup before clean: $dbPath to $copyPath"
        $dryRun = Read-Host "Dry run? (Y/N)"
        $confirm = Read-Host "Type CONFIRM DELETE to proceed with cleaning history for $($browser.Name) [$($browser.Profile)]"
        if ($confirm -eq 'CONFIRM DELETE') {
          if ($browser.Type -eq 'Chromium') {
            $sql1 = "DELETE FROM visits;"
            $sql2 = "DELETE FROM urls WHERE id NOT IN (SELECT url FROM visits);"
            $sql3 = "VACUUM;"
            if ($dryRun -eq 'Y') {
              Write-Host "Dry run: Would execute:"
              Write-Host $sql1
              Write-Host $sql2
              Write-Host $sql3
            } else {
              Query-Sqlite $dbPath $sql1
              Query-Sqlite $dbPath $sql2
              Query-Sqlite $dbPath $sql3
              Log "Cleaned Chromium history for $($browser.Name) [$($browser.Profile)]"
              Write-Host "History cleaned."
            }
          } elseif ($browser.Type -eq 'Firefox') {
            $sql1 = "DELETE FROM moz_historyvisits;"
            $sql2 = "DELETE FROM moz_places WHERE id NOT IN (SELECT place_id FROM moz_historyvisits);"
            $sql3 = "VACUUM;"
            if ($dryRun -eq 'Y') {
              Write-Host "Dry run: Would execute:"
              Write-Host $sql1
              Write-Host $sql2
              Write-Host $sql3
            } else {
              Query-Sqlite $dbPath $sql1
              Query-Sqlite $dbPath $sql2
              Query-Sqlite $dbPath $sql3
              Log "Cleaned Firefox history for $($browser.Name) [$($browser.Profile)]"
              Write-Host "History cleaned."
            }
          } else {
            Write-Host "Clean not supported for this browser."
          }
        } else {
          Write-Host "Confirmation failed. Aborting."
        }
        Read-Host "Press Enter to continue"
      } else {
        Write-Host "Invalid selection."
        Read-Host "Press Enter"
      }
    }
    '4' {
      Write-Host "Dry run not implemented in snippet"
      Read-Host "Press Enter"
    }
    '5' { break }
    default { Write-Host "Invalid option" }
  }
}

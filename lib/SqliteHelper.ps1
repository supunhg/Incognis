# SqliteHelper.ps1 - helper functions for SQLite queries
function Query-Sqlite($dbPath, $sql) {
  $sqlite = Join-Path $ScriptDir "bin\sqlite3.exe"
  if (-not (Test-Path $sqlite)) { throw "sqlite3.exe not found at $sqlite" }
  $cmd = "`"$sqlite`" --batch `"$dbPath`" `"$sql`""
  $out = & cmd /c $cmd
  return $out
}

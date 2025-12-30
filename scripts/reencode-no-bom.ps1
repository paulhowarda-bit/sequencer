# Re-encode Java sources in repo to UTF8 without BOM using .NET to avoid BOM
Get-ChildItem -Path 'src\main\java\com\example\aeron','src\test\java\com\example\aeron' -Filter *.java -Recurse | ForEach-Object {
    $p = $_.FullName
    Write-Host "Re-encoding $p"
    $content = Get-Content -Raw -LiteralPath $p
    [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Host "Done re-encoding."
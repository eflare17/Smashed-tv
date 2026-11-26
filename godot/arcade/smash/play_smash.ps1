# Plays Smash (the arcade mini-game) on its own. Started by "Play Smash.bat" in the repo's top folder.
# Finds Godot 4.4 on this PC (the GODOT environment variable, the PATH, or the usual folders), or offers to
# download Godot 4.4.1 once into %LOCALAPPDATA%\SmashedTV. The Godot it finds is remembered there for next time.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$project = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$store = Join-Path $env:LOCALAPPDATA 'SmashedTV'
$remember = Join-Path $store 'godot_path.txt'
$want = 'Godot_v4.4*_win64.exe'
$url = 'https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_win64.exe.zip'

function Find-Godot {
	if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
	if (Test-Path $remember) {
		$p = (Get-Content $remember -Raw).Trim()
		if ($p -and (Test-Path $p)) { return $p }
	}
	$cmd = Get-Command $want -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*console*' } | Select-Object -First 1
	if ($cmd) { return $cmd.Source }
	$places = @(
		(Join-Path $store 'godot'),
		[Environment]::GetFolderPath('Desktop'),
		(Join-Path $env:USERPROFILE 'Downloads'),
		[Environment]::GetFolderPath('MyDocuments'),
		(Join-Path $env:LOCALAPPDATA 'Programs'),
		$env:ProgramFiles,
		${env:ProgramFiles(x86)},
		'C:\Godot', 'D:\Godot', 'C:\Tools'
	)
	foreach ($dir in $places) {
		if (-not $dir -or -not (Test-Path $dir)) { continue }
		Write-Host "Looking for Godot 4.4 in $dir ..."
		$hit = Get-ChildItem -Path $dir -Filter $want -Recurse -Depth 4 -ErrorAction SilentlyContinue |
			Where-Object { $_.Name -notlike '*console*' } | Sort-Object Name -Descending | Select-Object -First 1
		if ($hit) { return $hit.FullName }
	}
	return $null
}

$godot = Find-Godot
if (-not $godot) {
	Write-Host ''
	Write-Host 'Godot 4.4 was not found on this PC.'
	$a = Read-Host "Download Godot 4.4.1 now (about 60 MB, into $store)? [Y/N]"
	if ($a -notmatch '^[Yy]') {
		Write-Host 'Not downloaded. You can also set the GODOT environment variable to your Godot 4.4 exe.'
		exit 1
	}
	New-Item -ItemType Directory -Force -Path $store | Out-Null
	$zip = Join-Path $store 'godot.zip'
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	Write-Host 'Downloading Godot 4.4.1 ...'
	Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
	Expand-Archive -Path $zip -DestinationPath (Join-Path $store 'godot') -Force
	Remove-Item $zip
	$godot = Find-Godot
	if (-not $godot) { throw 'Downloaded Godot but could not find the exe in the zip.' }
}
New-Item -ItemType Directory -Force -Path $store | Out-Null
Set-Content -Path $remember -Value $godot
Write-Host "Using $godot"

# a project never opened in the editor needs its first import (only done once)
if (-not (Test-Path (Join-Path $project '.godot\imported'))) {
	Write-Host 'First run: importing the project (a minute or two) ...'
	Start-Process -FilePath $godot -ArgumentList '--headless', '--path', "`"$project`"", '--import' -Wait -NoNewWindow
}

Start-Process -FilePath $godot -ArgumentList '--path', "`"$project`"", 'res://arcade/smash/smash.tscn'

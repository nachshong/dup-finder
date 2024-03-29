﻿$SCAN_LIST_PATH = "__SCAN-LIST.txt"
$ALBUM_LIST_PATH = "_ALBUMS.txt"
$FOLDER_LIST_PATH = "_FOLDERS.txt"

If (-Not (Test-Path $SCAN_LIST_PATH)) {
	"" > $SCAN_LIST_PATH
	Write-Output "Welcome to DupFinder!"
	Write-Output "Please enter the folders you want to scan in the '$SCAN_LIST_PATH' file (each folder in a new line)."
	Exit
}

$scope = Get-Content $SCAN_LIST_PATH
$albums = If (Test-Path $ALBUM_LIST_PATH)  { Get-Content $ALBUM_LIST_PATH } Else { @() }
$folders = If (Test-Path $FOLDER_LIST_PATH) { Get-Content $FOLDER_LIST_PATH } Else { @() }

Function Get-Hash
{
    Param (
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
		[String] $InputValue, 

		[ValidateSet("SHA1", "SHA256", "SHA384", "SHA512", "MACTripleDES", "MD5", "RIPEMD160")]
		$Algorithm = "MD5"
	)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputValue)
    $algo = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
	$hash = $algo.ComputeHash($bytes)
	[System.BitConverter]::ToString($hash).Replace("-", "")
}

$ht = @{}
$unk = @{}
$scope_hash = Get-Hash [string]$scope
$cache_file = "CACHE-$scope_hash.json"
$result_file = "~RESULT.txt"

Write-Output "DupFinder scan list contains $($scope.length) folders."
Write-Output "DupFinder albums list contains $($albums.length) items."
Write-Output "DupFinder folders list contains $($folders.length) items."

if (Test-Path $cache_file) {
	Write-Output "DupFinder using cache file: ""$cache_file""."
	$a = Get-Content $cache_file | ConvertFrom-Json
	foreach($h in $a.psobject.properties.name) { 
		$ht[$h] = @{}
		foreach ($p in $a.$h.psobject.properties.name) { if (Test-Path $p) { $ht[$h].Add($p, $a.$h.$p) } }
	}
} else {
	Write-Output "DupFinder scan started at " + [System.DateTime]::Now.ToString("s").Replace("T", " ")
	$a = Get-ChildItem -Path $scope -Recurse | Get-FileHash -Algorithm MD5	
	foreach($e in $a) {
		if (!$ht[$e.Hash]) { $ht[$e.Hash] = @{} }
		$ht[$e.Hash].Add($e.Path, $e)
	}
	Write-Output "DupFinder scan ended at " + [System.DateTime]::Now.ToString("s").Replace("T", " ")
}

# remove unique files from list
$keys = New-Object System.Collections.ArrayList($ht.keys)
foreach($k in $keys) {
	if ($ht[$k].count -eq 1) { $ht.Remove($k) }
}

ConvertTo-Json $ht -Compress > $cache_file

"# # # DupFinder " + [System.DateTime]::Now.ToString("s").Replace("T", " ") + " # # #" > $result_file

foreach($k in $ht.keys) {
	if ($k -Eq "D41D8CD98F00B204E9800998ECF8427E") { continue } # ignore empty files

	$d = $ht[$k]
	$p = New-Object System.Collections.ArrayList($d.keys)
	$p.Sort()
	$last_f = $null
	$last_i = ""
	foreach($i in $p) {
		$f = [System.IO.Path]::GetDirectoryName($i)
		$known = ($albums.Contains($f) -or $folders.Contains($f))

		if (-not $known) {
			$unk[$f] = $true
		}
		
		if ($null -eq $last_f) {
			$last_f = $f
			$last_i = $i
			continue;
		}
		
		$to_del = $null
		
		if ($f -eq $last_f) {
			if ([System.IO.Path]::GetExtension($i) -ne [System.IO.Path]::GetExtension($last_i)) { continue }		
		
			#remove dup in same folder
			if ($i.length -lt $last_i.length) {
				$to_del = $last_i
				$last_i = $i
			} else {
				$to_del = $i
			}
		} elseif ($known) {
			#remove dup on 2 known folders
			if (($folders.contains($f) -and $albums.contains($last_f)) -or ($folders.contains($f) -and $folders.contains($last_f) -and ($folders.indexof($last_f) -gt $folders.indexof($f)))) {
				$to_del = $i
			} else {
				if (($albums.contains($f) -and $folders.contains($last_f)) -or ($folders.contains($f) -and $folders.contains($last_f) -and ($folders.indexof($last_f) -lt $folders.indexof($f)))) {
					$to_del = $last_i
				}
				$last_f = $f
				$last_i = $i
			}
		}
		
		if ($null -ne $to_del) {
			"del ""$to_del"" -Force" >> $result_file
		}
	}
}

# list unknown folders
if ($unk.count -gt 0) {
	$unknowns = New-Object System.Collections.ArrayList($unk.keys)
	$unknowns.Sort()
	foreach ($u in $unknowns) {
		"# unknown folder: $u" >> $result_file
	}
}

$ht.values | Select-Object -ExpandProperty values | Format-Table -GroupBy Hash -Property Path >> $result_file

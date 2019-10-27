$scope = Get-Content __SCAN-LIST.txt
$albums = Get-Content _ALBUMS.txt
$folders = Get-Content _FOLDERS.txt

Function Get-Hash
{
    Param (
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
		[String] $String, 

		[ValidateSet("SHA1", "SHA256", "SHA384", "SHA512", "MACTripleDES", "MD5", "RIPEMD160")]
		$Algorithm = "MD5"
	)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($String)
    $algo = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
	$hash = $algo.ComputeHash($bytes)
	[System.BitConverter]::ToString($hash).Replace("-", "")
}

$ht = @{}
$unk = @{}
$scope_hash = Get-Hash [string]$scope
$cache_file = "CACHE-$scope_hash.json"
$result_file = "~RESULT.txt"

"DupFinder scope contains $($scope.length) folders."
"DupFinder albums list contains $($albums.length) items."
"DupFinder folders list contains $($folders.length) items."

if (Test-Path $cache_file) {
	"DupFinder using cache file: ""$cache_file""."
	$a = Get-Content $cache_file | ConvertFrom-Json
	foreach($h in $a.psobject.properties.name) { 
		$ht[$h] = @{}
		foreach ($p in $a.$h.psobject.properties.name) { if (Test-Path $p) { $ht[$h].Add($p, $a.$h.$p) } }
	}
} else {
	"DupFinder scan started at " + [System.DateTime]::Now.ToString("s").Replace("T", " ")
	$a = Get-ChildItem -Path $scope -Recurse | Get-FileHash -Algorithm MD5	
	foreach($e in $a) {
		if (!$ht[$e.Hash]) { $ht[$e.Hash] = @{} }
		$ht[$e.Hash].Add($e.Path, $e)
	}
	"DupFinder scan ended at " + [System.DateTime]::Now.ToString("s").Replace("T", " ")
}

# remove unique files from list
$keys = New-Object System.Collections.ArrayList($ht.keys)
foreach($k in $keys) {
	if ($ht[$k].count -eq 1) { $ht.Remove($k) }
}

ConvertTo-Json $ht -Compress > $cache_file

"# # # " + [System.DateTime]::Now.ToString("s").Replace("T", " ") + " # # #" > $result_file

foreach($k in $ht.keys) {
	if ($k -eq "D41D8CD98F00B204E9800998ECF8427E") { continue } # ignore empty files

	$d = $ht[$k]
	$p = New-Object System.Collections.ArrayList($d.keys)
	$p.Sort()
	$last_f = $null
	$last_i = ""
	foreach($i in $p) {
		$f = [System.IO.Path]::GetDirectoryName($i)
		$known = ($albums.contains($f) -or $folders.contains($f))

		if (-not $known) {
			$unk[$f] = $true
		}
		
		if ($last_f -eq $null) {
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
		
		if ($to_del -ne $null) {
			Echo "del ""$to_del"" -Force" >> $result_file
		}
	}
}

# list unknown folders
if ($unk.count -gt 0) {
	$unknowns = New-Object System.Collections.ArrayList($unk.keys)
	$unknowns.Sort()
	foreach ($u in $unknowns) {
		Echo "# unknown folder: $u" >> $result_file
	}
}

$ht.values | select -ExpandProperty values | Format-Table -GroupBy Hash -Property Path >> $result_file

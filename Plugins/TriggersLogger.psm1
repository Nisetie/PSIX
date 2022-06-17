$savePath = $rootPath + "\Live\TriggersLogger" + "\$($instance.HostName).txt"

if (test-path ($rootPath + "\Live\TriggersLogger")) {} 
else {
	New-Item -Path ($rootPath + "\Live\TriggersLogger") -ItemType Directory | out-null
}

$allTriggers = $instance.Checked;

if ($allTriggers.Count -eq 0) {
    if (Test-Path ($savePath)) { 
        Remove-Item -Path ($savePath)
    }
} else {
    $allTriggers | select * -ExcludeProperty Script, DescriptionScript | ConvertTo-JSON | Out-File -FilePath ($savePath) -force        
}

$allTriggers = $null;
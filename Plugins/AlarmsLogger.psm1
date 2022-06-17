$savePath = $rootPath + "\Live\AlarmsLogger" + "\$($instance.HostName).txt"

if (test-path ($rootPath + "\Live\Alarms")) {
    if (test-path ($savePath)) { }
} 
else {
	New-Item -Path ($rootPath + "\Live\AlarmsLogger") -ItemType Directory | out-null
}

$actualTriggers = $instance.Checked | where { $_.Status -eq $true};
$actualTriggers = ($actualTriggers | select * -ExcludeProperty Script, DescriptionScript);


if ($actualTriggers.Count -eq 0) {
    if (Test-Path ($savePath)) { 
        Remove-Item -Path ($savePath)
    }
} else {
    
    $actualTriggers | ConvertTo-JSON | Out-File -FilePath ($savePath) -force        
}

$actualTriggers = $null;

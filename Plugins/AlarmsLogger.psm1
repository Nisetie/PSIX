# Write triggers only with :true" checks

$savePath = [System.IO.Path]::Combine($rootPath,"Live","AlarmsLogger","$($instance.HostName).txt");

if (test-path ([System.IO.Path]::Combine($rootPath,"Live","AlarmsLogger"))) {} 
else {
	New-Item -Path ([System.IO.Path]::Combine($rootPath,"Live","AlarmsLogger")) -ItemType Directory | out-null
}

$actualTriggers = $instance.Checked | where { $_.Status -eq $true};
$actualTriggers = ($actualTriggers | select Host,Template,Item,@{Name="CheckTimestamp";Expression={$_.CheckTimestamp.ToString('o')} },Description -ExcludeProperty Script, DescriptionScript);


if ($actualTriggers.Count -eq 0) {
    if (Test-Path ($savePath)) { 
        Remove-Item -Path ($savePath)
    }
} else {
    
    $actualTriggers | ConvertTo-JSON -Depth 100 | Out-File -FilePath ($savePath) -force        
}

$actualTriggers = $null;

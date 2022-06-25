if (test-path ($rootPath + "\Live\Zabbix")) {} 
else {
	New-Item -Path ($rootPath + "\Live\Zabbix") -ItemType Directory | out-null
}

$binPath = 'C:\zabbix\bin\zabbix_sender.exe'

function To-Zabbix([string]$zabbixSenderPath,[string]$server,[int]$port,[string]$hostName,[string]$key,[string]$value) {
    $line = ($zabbixSenderPath + ' -z '+$server+' -p '+$port.ToString()+' -i ' + "$PSScriptRoot\zabbix_send.txt")
    if ((Test-Path -Path "$PSScriptRoot\zabbix_send.txt") -eq $true) {
        Remove-Item -Path $PSScriptRoot\zabbix_send.txt
    }
    [System.IO.File]::WriteAllBytes("$PSScriptRoot\zabbix_send.txt", [System.Text.Encoding]::UTF8.GetBytes($hostName + ' ' + $key + ' ' + $value));
    Invoke-Expression ('& ' + $line);
    Remove-Item -Path $PSScriptRoot\zabbix_send.txt
}

function To-Zabbix([string]$zabbixSenderPath,[string]$server,[int]$port,[string]$filename) {
    $line = ($zabbixSenderPath + ' -z '+$server+' -p '+$port.ToString()+' -i ' + $filename)
    $result = Invoke-Expression ('& ' + $line);
}

$zabbixSenderPath = $binPath;
$server = 'ip';
$port = port;
$hostName = "";
$key = "";
$value = "";

  
$Triggers = $instance.Checked;
$Triggers = ($Triggers | select * -ExcludeProperty Script, DescriptionScript);

$hostName= $instance.hostname;

$data = '';

foreach ($trigger in $triggers) {
        
        if ($Trigger.Template -eq [string]::Empty) { $key = "$($trigger.Item)"; }
        else { $key = "$($trigger.Template + '.' + $trigger.Item)"; }
        
        $value = "{`"data`":[{`"{#NAME}`":`"$key`",`"{#ID}`":`"$key`"}]}"

        $data += $hostName + ' ' + 'checks.lld' + ' ' + '"'+$value.Replace('"','\"') + '"' + [System.Environment]::NewLine;

        if ($trigger.Status -eq $true) { $value = 0; } else { $value = 1; $trigger.Description = ""; }

        $data += $hostName + ' ' + "checks[$key,result]" + ' ' + $value + [System.Environment]::NewLine;
        $data += $hostName + ' ' + "checks[$key,result_str]" + ' ' + ('"'+$trigger.Description.Replace('"','\"')+'"') + [System.Environment]::NewLine;
}


$filePath = "$rootPath" + "\Live\Zabbix" + "\$hostName.txt";
[System.IO.File]::WriteAllBytes($filePath, [System.Text.Encoding]::UTF8.GetBytes($data));
To-Zabbix $zabbixSenderPath $server $port $filePath

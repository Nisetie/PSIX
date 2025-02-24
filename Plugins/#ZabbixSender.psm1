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
    return $result;
}

function Append-AllBytes([string] $path, [byte[]] $bytes)
{
    [System.IO.FileMode]$fm = [System.IO.FileMode]::Append;
    $stream = new-object 'System.IO.FileStream'  -ArgumentList @($path,[System.IO.FileMode]::Append)  
    $stream.Write($bytes, 0, $bytes.Length);    
    $stream.Close()
}

$zabbixSenderPath = $binPath;
$server = '172.24.29.5';
$port = 10052;
$hostName = "";
$key = "";
$value = "";

$t2 = $null;

if (test-path ("$rootPath" + "\Live\Zabbix\" + "$($currentHost.HostName)_PrevTriggers.txt")) {
    $t2 = Get-Content ("$rootPath" + "\Live\Zabbix\" + "$($currentHost.HostName)_PrevTriggers.txt") -Raw;
    if ($t2 -ne $null) {
        $t2 = ConvertFrom-Json -InputObject $t2;
        }
    else {
        $t2 = @();
    }
	Set-Content -path ("$rootPath" + "\Live\Zabbix\" + "$($currentHost.HostName)_PrevTriggers.txt") -Value '';
} 

if (($t2 -is [System.Array]) -eq $False) {
	$t2 = @($t2);
}

$t2 = New-Object 'System.Collections.Generic.List[object]' (,$t2)

$oldTriggers = New-Object 'System.Collections.ArrayList';
  
$Triggers = $instance.Checked;
$Triggers = ($Triggers | select * -ExcludeProperty Script, DescriptionScript);

$hostName= $instance.hostname;

$data = '';

$filePath = "$rootPath" + "\Live\Zabbix" + "\$hostName.txt";

Set-Content $filePath '' -NoNewline -force;

foreach ($trigger in $triggers) {

	$data = '';
        
    if ($Trigger.Template -eq [string]::Empty) { $key = "$($trigger.Item)"; }
    else { $key = "$($trigger.Template + '.' + $trigger.Item)"; }
        
    $value = "{`"data`":[{`"{#NAME}`":`"$key`",`"{#ID}`":`"$key`"}]}"

    $data += $hostName + ' ' + 'checks.lld' + ' ' + '"'+$value.Replace('"','\"') + '"' + [System.Environment]::NewLine;

    if ($trigger.Status -eq $true) { $value = 0; } else { $value = 1; $trigger.Description = ""; }

	for ($i=0; $i -lt $t2.Count; $i++) {
		$oldTrigger = $t2[$i];
		if ($key -eq $oldTrigger.Key)  {
			[void]$t2.removeat($i);
			if ($value -eq $oldTrigger.Value -and $trigger.Description -ne $OldTrigger.Description) {
				$data += $hostName + ' ' + "checks[$key,result]" + ' 1'+ [System.Environment]::NewLine;
				$data += $hostName + ' ' + "checks[$key,result_str]" + ' ' + '""' + [System.Environment]::NewLine;
				break;	
			}					
		}
	}

    $data += $hostName + ' ' + "checks[$key,result]" + ' ' + $value + [System.Environment]::NewLine;
    $data += $hostName + ' ' + "checks[$key,result_str]" + ' ' + ('"'+$trigger.Description.Replace('"','\"')+'"') + [System.Environment]::NewLine;
	
	[void]$oldTriggers.Add(@{Key = $key;Value=$value;Description=$trigger.Description});

	$b = [System.Text.Encoding]::UTF8.GetBytes($data);
	Append-AllBytes $filePath $b
}

foreach ($oldTrigger in $t2) {
	[void]$oldTriggers.Add($oldTrigger);
}

$oldTriggers | ConvertTo-JSON | Out-File -FilePath ("$rootPath" + "\Live\Zabbix\" + "\$($currentHost.HostName)_PrevTriggers.txt") -force 

$data = '';

$metrics = new-object 'System.Collections.Generic.Dictionary[string,string]';
$metrics.Add('FQDN',$instance.FQDN);
$metrics.Add('IP',$instance.IP);
$instance.updateScripts | %{ 
    $metrics.Add($_.ElementName,'"'+$_.CurrentValue.ToString().Replace('"','\"')+'"');	
}
$instance.templates | %{
	$tName = $_.TemplateName;
 	$_.updateScripts | %{
            $metrics.Add("$tName.$($_.ElementName)",'"'+$_.CurrentValue.ToString().Replace('"','\"')+'"');	
	}
}

foreach ($key in $metrics.Keys) {
	$data = '';

    $data += $hostName + ' ' + 'metrics.lld' + ' ' + '"'+"{`"data`":[{`"{#NAME}`":`"$key`",`"{#ID}`":`"$key`"}]}".Replace('"','\"') + '"' + [System.Environment]::NewLine;
    $data += $hostName + ' ' + "metrics[$key,value]" + ' ' + $metrics[$key] + [System.Environment]::NewLine;
	
	$b = [System.Text.Encoding]::UTF8.GetBytes($data);
	Append-AllBytes $filePath $b
}


(To-Zabbix $zabbixSenderPath $server $port $filePath) | Add-Content -path $filePath;

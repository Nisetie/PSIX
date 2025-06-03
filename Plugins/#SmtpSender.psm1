
<#
- укажи электронный ящик отправителя
- укажи электронный ящик получателя
- укажи сервер SMTP
- укажи логин и пароль учетной записи для подключения к почтовому ящику
#>

$liveCatalog = ([System.IO.Path]::Combine($rootPath,"Live","Smtp"));

if (test-path $liveCatalog) {} 
else {	New-Item -Path $liveCatalog -ItemType Directory | out-null }

$from = [mailaddress]::new("...");
$to = [mailaddress]::new("...");

$msg = [System.Net.Mail.MailMessage]::new();
$msg.From = $from;
$msg.To.Add($to);
#$msg.To.Add($from);
$msg.Subject = "PSIX Info";

$client = [System.Net.Mail.SmtpClient]::new('smtpServer',587);
$client.Credentials = [pscredential]::new("login", (ConvertTo-SecureString -String "password" -AsPlainText -Force) )

$hostName = "";
$key = "";
$value = "";

$prevTriggers = $null;
if (test-path ([System.IO.Path]::Combine( $liveCatalog, "$($currentHost.HostName)_PrevTriggers"))) {
    $prevTriggers = GetContent ([System.IO.Path]::Combine( $liveCatalog, "$($currentHost.HostName)_PrevTriggers"));
    if ($prevTriggers -ne $null) {
        $prevTriggers = ConvertFrom-Json -InputObject $prevTriggers;
        }
    else {
        $prevTriggers = @();
    }
} 

if (($prevTriggers -is [System.Array]) -eq $False) { $prevTriggers = @($prevTriggers); }
$prevTriggers = New-Object 'System.Collections.Generic.List[object]' (,$prevTriggers)

$oldTriggers = New-Object 'System.Collections.ArrayList';
  
$Triggers = $instance.Checked;
$Triggers = ($Triggers | select * -ExcludeProperty Script, DescriptionScript);

$hostName= $instance.hostname;

$data = $null;

# https://adamtheautomator.com/html-report/
$html = @'
<style>
    h1 {

        font-family: Arial, Helvetica, sans-serif;
        color: #e68a00;
        font-size: 28px;
    }    
    h2 {
        font-family: Arial, Helvetica, sans-serif;
        color: #000099;
        font-size: 16px;
    }    
   table {
		font-size: 12px;
		border: 0px; 
		font-family: Arial, Helvetica, sans-serif;
	}	
    td {
		padding: 4px;
		margin: 0px;
		border: 0;
	}	
    th {
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 11px;
        text-transform: uppercase;
        padding: 10px 15px;
        vertical-align: middle;
	}
    tbody tr:nth-child(even) {
        background: #f0f0f2;
    }
    #CreationDate {

        font-family: Arial, Helvetica, sans-serif;
        color: #ff3300;
        font-size: 12px
    }
    .BadStatus {
        color: #ff0000;
    }  
    .GoodStatus {
        color: #008000;
    }
</style>
'@;

$html += @'
<table>
<colgroup><col/><col/><col/><col/><col/><col/></colgroup>
<tr><th>Timestamp</th><th>OkTimestamp</th><th>Host</th><th>IP</th><th>TriggerName</th><th>Description</th></tr>
'@;

$forCSSBadStatus = 'class ="BadStatus"';
$forCSSGoodStatus = 'class ="GoodStatus"';

$newTriggersCount = 0;
$okTriggers = 0;

foreach ($trigger in $triggers) {

    if ($Trigger.Template -eq [string]::Empty) { $key = "$($trigger.Item)"; }
    else { $key = "$($trigger.Template + '.' + $trigger.Item)"; }


    if ($trigger.Status -eq $true) { $newTriggersCount++; }

     $data = @{
        Status = $trigger.Status;
        Timestamp = $trigger.CheckTimestamp.ToString('o');
        OkTimestamp = $null;
        Host  = $currentHost.HostName;
        IP = $currentHost.IP;
        TriggerName = $key;
        Description = $trigger.Description;
    }

	for ($i=0; $i -lt $prevTriggers.Count; $i++) {
		$prevTrigger = $prevTriggers[$i];
		if ($key -eq $prevTrigger.TriggerName)  {
            $newTriggersCount--;
            [void]$prevTriggers.removeat($i);
            $i--;
            if ($trigger.Status -eq $false -and $prevTrigger.Status -eq $true) {
                $okTriggers++;
                $data.OkTimestamp = $data.Timestamp;
                $data.Timestamp = $prevTrigger.Timestamp;
            }
            elseif ($trigger.Status -eq $true -and $prevTrigger.Status -eq $true -and $trigger.Description -ne $prevTrigger.Description) {
                $newTriggersCount++;
            }
            break;
		}
	}

	if ($data.Status -eq $true -or ($data.Status -eq $False -and $data.OkTimestamp -ne $null)) { 
        
        [void]$oldTriggers.Add($data); 

        $html += @"
<tr $(if ($data.Status -eq $true){$forCSSBadStatus}else{$forCSSGoodStatus})><td>$($data.Timestamp)</td><td>$($data.OkTimestamp)</td><td>$($data.Host)</td><td>$($data.IP)</td><td>$($data.TriggerName)</td><td>$($data.Description)</td></tr>
"@;
    }
}

$html += @'
</table>
'@;

foreach ($prevTrigger in $prevTriggers) { [void]$oldTriggers.Add($prevTrigger); }

$oldTriggers | ConvertTo-JSON -Depth 100 | Out-File -FilePath ( [System.IO.Path]::Combine( $liveCatalog,"$($currentHost.HostName)_PrevTriggers")) -force 
$html = ConvertTo-Html -Body $html -Title ($currentHost.HostName);
Out-File -FilePath  ([System.IO.Path]::Combine( $liveCatalog,"$($currentHost.HostName)_web.html")) -InputObject $html;

if ($newTriggersCount -gt 0 -or $okTriggers -gt 0){
    $msg.Subject = "PSIX: $($currentHost.Hostname)";
    $msg.Body = $html;
    $msg.IsBodyHtml = $true;
    try{ $client.Send($msg); Remove-Item -Path ([System.IO.Path]::Combine( $liveCatalog,"$($currentHost.HostName)_error")) -Force} 
    catch { Out-File -FilePath ([System.IO.Path]::Combine( $liveCatalog,"$($currentHost.HostName)_error")) -InputObject $_; }
}



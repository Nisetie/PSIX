$currentHost = $instance;

$liveMetricsPath = [System.IO.Path]::Combine($rootPath,"Live","MetricsLogger");

if (test-path $liveMetricsPath) {} 
else {
	New-Item -Path $liveMetricsPath -ItemType Directory | out-null
}

$t2 = $null;

if (test-path ([System.IO.Path]::Combine($liveMetricsPath,"$($currentHost.HostName).txt"))) {
    $t2 = GetContent ([System.IO.Path]::Combine($liveMetricsPath,"$($currentHost.HostName).txt"));
    $t2 = ConvertFrom-Json -InputObject $t2;
} 

$h =  @{
    HostName = $currentHost.hostName
    FQDN = $currentHost.FQDN
    IP = $currentHost.ip
    ping = $currentHost.ping
    UpdateTimestamp = $currentHost.UpdateTimestamp.ToString('o')
    UpdateDelta = $currentHost.UpdateDelta.ToString()
    UpdateDeltaTotal = $currentHost.UpdateDeltaTotal.ToString();
    UpdateDeltaTemplates = $currentHost.UpdateDeltaTemplates.ToString();
};
        
$currentHost.updateScripts.GetEnumerator() | %{ $h.($_.Value.ElementName) = @{ Value =  "$($_.Value.CurrentValue)";  UpdateTimestamp =  $_.Value.UpdateTimestamp.ToString('o')}  }

$templates = @();

$templates += $currentHost.templates.GetEnumerator() | %{
        $r = @{};
        $r.TemplateName = $_.Value.updateScripts[0].templateName
        $r.UpdateDelta = $_.Value.UpdateDelta.ToString()
        $_.Value.updateScripts.GetEnumerator() | %{ $r.($_.Value.ElementName) = @{ Value = "$($_.Value.CurrentValue)";UpdateTimestamp =  $_.Value.UpdateTimestamp.ToString('o')}  }
        return $r;
    }
        
$data= @{
    Host = $h
    Templates = $templates 
};    

if ($t2 -ne $null) {
    foreach ($property in $t2.Host.psobject.Properties) {
        if ($data.Host.Keys -notcontains $property.Name) {
            $data.Host.$($property.Name) = $t2.Host.$($property.Name)
        }    
    }
    $templates1 = $data.Templates.TemplateName;
    foreach ($template in $t2.Templates) {
        if ($templates1 -notcontains $template.TemplateName) { 
            $t = @{};
            foreach ($property in $template.psobject.Properties) {
                $t.$($property.Name) = $template.$($property.Name);
            }
    
            $data.Templates += $t;
        }     
    }
}

$data | ConvertTo-JSON -Depth 100 | Out-File -FilePath ( [System.IO.Path]::Combine($liveMetricsPath,"$($currentHost.HostName).txt") ) -force 

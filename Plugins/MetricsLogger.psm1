$currentHost = $instance;

if (test-path ($rootPath + "\Live\MetricsLogger\")) {} 
else {
	New-Item -Path ($rootPath + "\Live\MetricsLogger\") -ItemType Directory | out-null
}

$t2 = $null;

if (test-path ("$rootPath" + "\Live\MetricsLogger\" + "\$($currentHost.HostName).txt")) {
    $t2 = Get-Content ("$rootPath" + "\Live\MetricsLogger\" + "\$($currentHost.HostName).txt") -Raw;
    $t2 = ConvertFrom-Json -InputObject $t2;
} 

$h =  @{
    HostName = $currentHost.hostName
    FQDN = $currentHost.FQDN
    IP = $currentHost.ip
    ping = $currentHost.ping
    UpdateDelta = $currentHost.UpdateDelta.ToString()
    UpdateDeltaTotal = $currentHost.UpdateDeltaTotal.ToString();
    UpdateDeltaTemplates = $currentHost.UpdateDeltaTemplates.ToString();
};
        
$currentHost.updateScripts | %{ $h.($_.ElementName) = "$($_.CurrentValue)";  }

$templates = @();

$templates += $currentHost.templates | %{
        $r = @{};
        $r.TemplateName = $_.updateScripts[0].templateName
        $r.UpdateDelta = $_.UpdateDelta.ToString()
        $_.updateScripts | %{ $r.($_.ElementName) = "$($_.CurrentValue)";  }
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
      

$data | ConvertTo-JSON | Out-File -FilePath ( "$rootPath" + "\Live\MetricsLogger\" + "\$($currentHost.HostName).txt" ) -force 

if (test-path ($rootPath + "\Live\MetricsLogger\")) {} 
else {
	New-Item -Path ($rootPath + "\Live\MetricsLogger\") -ItemType Directory | out-null
}

$currentHost = $instance;

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
        
$data= @{
    Host = $h
    Templates = ($currentHost.templates | %{
        $r = @{};
        $r.TemplateName = $_.updateScripts[0].templateName
        $r.UpdateDelta = $_.UpdateDelta.ToString()
        $_.updateScripts | %{ $r.($_.ElementName) = "$($_.CurrentValue)";  }
        return $r;
    } ) 
};           

$data | ConvertTo-JSON | Out-File -FilePath ( "$rootPath" + "\Live\MetricsLogger\" + "\$($currentHost.HostName).txt" ) -force 
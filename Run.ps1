param($groups=$null,$hosts=$null,$templates=$null,$hostsIgnore=$null,$groupsIgnore=$null,$templatesIgnore=$null)
import-module ($PSScriptRoot +  ".\CoreLibrary.psm1")

# LOADING PLUGINS
$plugins = new-object System.Collections.Generic.List[object];
if ((Test-Path ("$PSScriptRoot\Plugins\")) -eq $true) {
    Get-ChildItem -Path "$PSScriptRoot\Plugins\" | %{ $plugins.Add($_.BaseName); }
}
for ($i = 0; $i -lt $plugins.Count; ++$i) {
    $pluginName = $plugins[$i].Trim();
    if ($pluginName -eq [string]::Empty -or $pluginName[0] -eq '#') { continue; }
    $plugins[$i] = (Get-Content -Path $PSScriptRoot\Plugins\$pluginName.psm1 -Raw);
}

# CHECK FILTERS

if ($groups -ne $null) { $groups = $groups.Split(","); }
if ($hosts -ne $null) { $hosts = New-Object 'System.Collections.Generic.List[string]' (,$hosts.Split(",")); } else { $hosts = New-Object 'System.Collections.Generic.List[string]'; } 
if ($templates -ne $null) { $templates = $templates.Split(","); }
if ($groupsIgnore -ne $null) { $groupsIgnore = $groupsIgnore.Split(","); }
if ($hostsIgnore -ne $null) { $hostsIgnore = $hostsIgnore.Split(","); }
if ($templatesIgnore -ne $null) { $templatesIgnore = $templatesIgnore.Split(","); }

if ($groups -ne $null) {
    $hostsInGroups = New-Object 'System.Collections.Generic.List[string]';
    foreach ($group in $groups) {
        $hostsInGroup = Get-Content ("$PSScriptRoot\HostGroups\$group\hosts.txt");
        foreach ($hostInGroup in $hostsInGroup) {
            $hostsInGroups.Add($hostInGroup);   
        }
    }

    $hosts.AddRange($hostsInGroups);
}

if ($groupsIgnore -ne $null) {
    $hostsInGroups = New-Object 'System.Collections.Generic.List[string]';
    foreach ($group in $groups) {
        $hostsInGroup = Get-Content ("$PSScriptRoot\HostGroups\$group\hosts.txt");
        foreach ($hostInGroup in $hostsInGroup) {
            [void] $hosts.RemoveAll( { param($match) $match -eq $hostsInGroup } );
        }
    }
}

if ($hostsIgnore -ne $null) {
    foreach ($hostIgnore in $hostsIgnore) {
        [void] $hosts.RemoveAll( { param($match) $match -eq $hostIgnore } );
    }
}

write ("Groups: $groups")
write ("Hosts: $hosts")
write ("Templates: $templates")
write ("Groups ignore: $groupsIgnore")
write ("Hosts ignore: $hostsIgnore")
write ("Templates ignore: $templatesIgnore")

$hostsFiles = Get-ChildItem -Path ("$PSScriptRoot\RuntimeHosts") | where { $hosts.Count -eq 0 -or $_.BaseName -in $hosts }

$RunspacePool = [runspacefactory]::CreateRunspacePool(1,10)
$RunspacePool.Open()

$Runspaces = @();

$mainScript = {
	param(
        [string]$hostName,
        [string]$usingPath,
        [System.Collections.Generic.List[object]]$pluginsList,
        [string]$rootPath, #for plugins
        [object]$filters #template filter
    )

    $runScript =@"
using module $usingPath        

param(`$filters)

`$instance = new-object $hostName        
`$instance.InitializeData(`$filters.Include,`$filters.Exclude);        
`$instance.Update();            
`$instance.Check();            
"@;

    for ($it=0; $it -lt $pluginsList.Count; ++$it) { 
        $runScript += $pluginsList[$it].ToString() + [System.Environment]::NewLine; 
    }

    [scriptblock]::Create($runScript).InvokeReturnAsIs($filters);
};

for ($i = 0; $i -lt $hostsFiles.Count; ++$i) {

    $PSInstance = [powershell]::Create();
    [void]$PSInstance.AddScript($mainScript);
    [void]$PSInstance.Addparameter('hostName',($hostsFiles[$i].BaseName))
    [void]$PSInstance.AddParameter('usingPath',$hostsFiles[$i].FullName)
    [void]$PSInstance.AddParameter('pluginsList',$plugins)
    [void]$PSInstance.AddParameter('rootPath',$PSScriptRoot);
    [void]$PSInstance.AddParameter('filters',@{Include=$templates;Exclude=$templatesIgnore});

    $PSInstance.RunspacePool = $RunspacePool

    $Runspaces += New-Object psobject -Property @{
	    HostName = $hostsFiles[$i].BaseName
        Instance = $PSInstance
        IAResult = $null
    }
}


write ('[' + (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffff") + '] ' + "Сканирование началось.");

for ($i = 0; $i -lt $Runspaces.Count; ++$i) { 
	$iaResult = $Runspaces[$i].Instance.BeginInvoke(); 
	$Runspaces[$i].IAResult = $iaResult; 
}

# Wait for the the runspace jobs to complete      
$completed = $true;
while ($true) {
    $completed = $true;
    for ($i = 0; $i -lt $Runspaces.Count; ++$i) {
        if ($Runspaces[$i].IAResult.IsCompleted -eq $false) {
            $completed = $false;
            break;
        }
    }
    if ($completed -eq $true) { break; } 
    else { sleep -Milliseconds 100; }
}
    

for ($i = 0; $i -lt $Runspaces.Count; ++$i) {
    $data = $Runspaces[$i].Instance.EndInvoke($Runspaces[$i].IAResult);
	if ($data -ne $null) { 
        Write-Host($Runspaces[$i].HostName) -ForegroundColor Red; 
        Write-Output $data; 
    }
}

write ('[' + (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffff") + '] ' + "Завершено." );

$RunspacePool.Close();
$RunspacePool.Dispose();

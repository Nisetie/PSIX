using module .\CoreLibrary.psm1

param([string]$targetPath=$null)

function Oneshot() {

    if ([string]::IsNullOrEmpty($targetPath)) { $targetPath = $PSScriptRoot; }

    # LOADING PLUGINS
    $plugins = new-object System.Collections.Generic.List[object];
    if ((Test-Path ([System.IO.Path]::Combine($PSScriptRoot,"Plugins"))) -eq $true) {
        Get-ChildItem -Path ([System.IO.Path]::Combine($PSScriptRoot,"Plugins")) | %{ $plugins.Add($_); }
    }
    for ($i = 0; $i -lt $plugins.Count; ++$i) {
        $pluginName = $plugins[$i].BaseName.Trim();
        if ($pluginName -eq [string]::Empty -or $pluginName[0] -eq '#') { continue; }
        $plugins[$i] = GetContent ($plugins[$i].FullName);
    }
      
    $hostsFiles = Get-ChildItem -Path ([System.IO.Path]::Combine($targetPath,"RuntimeHosts"))

    $RunspacePool = [runspacefactory]::CreateRunspacePool(1,[System.Environment]::ProcessorCount)
    $RunspacePool.Open()

    $Runspaces = @();

    $mainScript = {
	    param(
            [string]$hostName,
            [string]$usingPath,
            [System.Collections.Generic.List[object]]$pluginsList,
            [string]$rootPath #for plugins
        )

        $runScript =@"
using module $usingPath        

`$instance = new-object $hostName            
`$instance.Update();            
`$instance.Check();            
"@;

        for ($it=0; $it -lt $pluginsList.Count; ++$it) { 
            $runScript += $pluginsList[$it].ToString() + [System.Environment]::NewLine; 
        }

        $runScriptResult = [scriptblock]::Create($runScript).InvokeReturnAsIs($null);
        if ($runScriptResult -ne $null) { Write-Output $runScriptResult; }
    };

    for ($i = 0; $i -lt $hostsFiles.Count; ++$i) {

        $PSInstance = [powershell]::Create();
        [void]$PSInstance.AddScript($mainScript);
        [void]$PSInstance.Addparameter('hostName',($hostsFiles[$i].BaseName))
        [void]$PSInstance.AddParameter('usingPath',$hostsFiles[$i].FullName)
        [void]$PSInstance.AddParameter('pluginsList',$plugins)
        [void]$PSInstance.AddParameter('rootPath',$targetPath);

        $PSInstance.RunspacePool = $RunspacePool

        $Runspaces += New-Object psobject -Property @{
	        HostName = $hostsFiles[$i].BaseName
            Instance = $PSInstance
            IAResult = $null
        }
    }


    Write-Output ('[' + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + '] ' + 'Scanning...');

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
            Write-Output $data; 
        }
    }

    Write-Output ('[' + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + '] ' + 'Finish.' );

    $RunspacePool.Close();
    $RunspacePool.Dispose();
    $RunspacePool = $null;
    $Runspaces = $null;
    $mainScript = $null;

    $plugins = $null;
    $groups = $null;
    $hosts = $null;
    $templates = $null;
    $groupsIgnore = $null;
    $hostsIgnore = $null;
    $templatesIgnore = $null;
    $hostsInGroups = $null;
    $hostsFiles = $null;

    [System.GC]::Collect();
    [System.GC]::WaitForPendingFinalizers();

}

$lockFile = [System.IO.Path]::Combine($targetPath,".lock");
$waitCount = 60;
$success = $false;

cls;
while ($true) {
    try {
        $FileStream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None);
        Oneshot;
        $success = $true;
    
    } catch {
        cls
        if ($FileStream -eq $null) {
            Write-Host "[$([datetime]::Now.ToString("yyyy-MM-dd HH:mm:ss"))] Waiting lockfile...";
            sleep -Seconds 1;
            $waitCount--;
            if ($waitCount -gt 0) { goto begin; }
        } else {
            $Error | Write-Host;
            $Error.Clear();
        }
    } finally {
        if ($FileStream) {
            $FileStream.Close()
            $FileStream.Dispose()
            Remove-Item -Path $lockFile -Force;
            
        }
    }

    if ($success) { break; }
}
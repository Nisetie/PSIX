using module ".\CoreLibrary.psm1"

param([string]$targetPath=$null);

cls;

if ([string]::IsNullOrEmpty($targetPath)) { 
    Write-Output "Target path argument is empty!";
    return;
    #$targetPath = $PSScriptRoot; 
}
if ($targetPath -eq $PSScriptRoot) { 
    Write-Output "Target path cannot be in PSIX's core root!";
    return;
}

# --- INCLUDE


# --- INITIALIZATION

$initialLocation = Get-Location;
Set-Location $targetPath;

[bool]$DEBUG = $true;

$tempPath = [System.IO.Path]::Combine($targetPath,"RuntimeHosts");
if (test-path $tempPath) {
	Get-ChildItem -Path $tempPath | %{ $_.Delete(); }
} else {
	New-Item -Path $tempPath -ItemType Directory | out-null;
}

$tempPath = [System.IO.Path]::Combine($targetPath,"RuntimeTemplates");
if (test-path $tempPath) {
	Get-ChildItem -Path $tempPath | %{ $_.Delete(); }
} else {
	New-Item -Path $tempPath -ItemType Directory | out-null
}

$hostGroups = New-Object "System.Collections.Generic.Dictionary[string,[System.Collections.Generic.List[object]]]";
$hosts = New-Object "System.Collections.Generic.List[object]";
$templates = New-Object "System.Collections.Generic.List[object]";

# STEP 1. TEMPLATES. SCAN.
Write-Host "Search for templates. Begin..." -ForegroundColor Black -BackgroundColor Green;

if ($targetPath -ne $PSScriptRoot) {
    $tempPath = [System.IO.Path]::Combine($PSScriptRoot,"Templates");
    if ((test-path $tempPath) -eq $false) {
	    New-Item -Path $tempPath -ItemType Directory | out-null
    }
}

$tempPath = [System.IO.Path]::Combine($targetPath,"Templates");
if ((test-path $tempPath) -eq $false) {
	New-Item -Path $tempPath -ItemType Directory | out-null
}
Set-Location $tempPath;

Write-Host "Search for templates. Catalog: " (Get-Location).ToString();

if ($targetPath -eq $PSScriptRoot) {
    $templatesCatalog = Get-ChildItem -Directory | ?{$_.Name[0] -ne "#"};
} else {
    $templatesCatalog = (Get-ChildItem -Path ([System.IO.Path]::Combine($PSScriptRoot,"Templates")) -Directory | Where-Object{$_.Name[0] -ne "#"}) + (Get-ChildItem -Directory | ?{$_.Name[0] -ne "#"});
}

# STEP 2. TEMPLATES. PARSE.
foreach ($template in $templatesCatalog) {

    if ($template.BaseName[0] -eq '#') { continue; }

    $script = ParseTemplateCatalog $template.FullName; 

    try { # testing scripts
        Invoke-Expression -Command $script.body;
    } catch {
        Write-Output ($script.body)
        Write-Output "";
        $_
    }

    [string]$runtimePath = [System.IO.Path]::Combine($targetPath,"RuntimeTemplates",$template.BaseName+".psm1");

    $usingModulesString = "using module $PSScriptRoot\CoreLibrary.psm1;$([System.Environment]::NewLine)";

    SetContent $runtimePath ($usingModulesString + $script.body);

    $templates.Add(
    @{
        TemplateName=$template.BaseName;
        Body = $script.body
    });
}

Write-Host ("Search for templates. End. Templates: " + $templatesCatalog.Length.ToString());

# STEP 3. HOSTS GROUPS. SCAN.
Write-Host "Search for hosts groups. Begin..." -ForegroundColor Black -BackgroundColor Green;

$tempPath = [System.IO.Path]::Combine($targetPath,"HostGroups");
if ((test-path $tempPath) -eq $false) {
	New-Item -Path $tempPath -ItemType Directory | out-null
}
Set-Location $tempPath;

Write-Host "Search for hosts groups. Catalog: " (Get-Location).ToString();

$hostGroupCatalogs = Get-ChildItem -Directory | ?{$_.Name[0] -ne "#"};

# STEP 4. HOSTS GROUPS. PARSE.
foreach ($hostGroupCatalog in $hostGroupCatalogs) {

    if ($hostGroupCatalog.BaseName[0] -eq '#') { continue; }

    Write-Host ("Processing host groups... " + $hostGroupCatalog.ToString());

    $llds = new-object 'System.Collections.Generic.List[object]';
    if (test-path ([System.IO.Path]::Combine($hostGroupCatalog.FullName,"lld"))) {
        $lldsDirs = Get-ChildItem -Path ([System.IO.Path]::Combine($hostGroupCatalog.FullName,"lld")) -Directory;
        foreach ($lldDir in $lldsDirs) {
            $llds.Add((ParseLLDCatalog -path $lldDir.FullName));
        }
    }

    $hostsListFile = Get-ChildItem -Path $hostGroupCatalog -File -Filter "hosts";
    if ($hostsListFile.Count -eq 0) { continue; }
    $hostsList = GetContent $hostsListFile.FullName;
    $hostsList = $hostsList.Split([Environment]::NewLine,[System.StringSplitOptions]::RemoveEmptyEntries);

    $templatesListFile = Get-ChildItem -Path $hostGroupCatalog -File -Filter "templates";
    if ($templatesListFile.Count -eq 0) { $templatesList = $null; }
    else {
        $templatesList = GetContent $templatesListFile.FullName; 
        $templatesList = $templatesList.Split([Environment]::NewLine,[System.StringSplitOptions]::RemoveEmptyEntries);
    }

    foreach ($hostName in $hostsList){    
        $hostName = $hostName.ToLower();
        if ($hostGroups.ContainsKey($hostName) -eq $false) {
            $hostGroups[$hostName] = New-Object "System.Collections.Generic.List[object]";
            $hostGroups[$hostName].Add((New-Object "System.Collections.Generic.List[string]")); #templates
            $hostGroups[$hostName].Add((new-object 'System.Collections.Generic.List[object]')); #llds
        }

        $hostGroups[$hostName][1].AddRange($llds);

        foreach($template in $templatesList) {
            $template = $template.Trim();
            if ( ($templates | where { $_.TemplateName -eq $template }) -eq $null ) {
		write-host "error template $template" -ForegroundColor Red;
                continue; #if not exitst
            }
            if ($template -ne [string]::Empty -and $hostGroups[$hostName][0].Contains($template) -eq $false) {
                $hostGroups[$hostName][0].Add($template)
            }
        }
    }
}

Write-Host ("Search for hosts groups. End. " + $hostGroupCatalogs.Length.ToString() + " groups...");

# ������������ �������� ������ � �� ��������
Write-Host "Hosts scan. Begin..." -ForegroundColor Black -BackgroundColor Green;

$tempPath = [System.IO.Path]::Combine($targetPath,"Hosts");

if ((test-path $tempPath) -eq $false) {
	New-Item -Path $tempPath -ItemType Directory | out-null
}

Set-Location $tempPath;

Write-Host ("Hosts scan. Catalog: " + (Get-Location).ToString());

$hostCatalogs = Get-ChildItem -Directory | ?{$_.Name[0] -ne "#"}

Write-Host ("Hosts: " + $hostCatalogs.Length.ToString());

foreach ($remoteHost in $hostCatalogs) {

    if ($remoteHost.BaseName[0] -eq '#') {
        continue;
    }

	$hostName = '';
	$hostAddress = '';
	$fileName = $remoteHost.BaseName;
	$fileNameParts = $fileName.Split(' ');
	if ($fileNameParts.Length -gt 1) {
		$hostName = $fileNameParts[0];
		$hostAddress = $fileNameParts[1];
	}
	else {
		$hostName=$hostAddress=$fileName;
	}

    $script = ParseHostCatalog $remoteHost.FullName; 

    $additionalText = '';
    
    if ($hostGroups.ContainsKey($hostName.ToLower()) -eq $true) {

        $templatesList = $hostGroups[$hostName.ToLower()][0];
        $templateGroupBody = "";
        foreach ($template in $templatesList) {
            if ($script.Templates.Contains($template) -eq $false) {
                $script.Templates.Add($template);
            }
            $templateGroupBody += ("`$this.templates.Add(`$this.templates.Count, [" + $template + "]::new(`$this));`r`n`t");
        }

        $llds = $hostGroups[$hostName.ToLower()][1];
        foreach ($lld in $llds) {
            $metrics = $null;
            if ($lld.invokation -eq [Invokation]::REMOTE) {                    
                $metrics = Invoke-Command -ComputerName ($hostName) -scriptblock  $lld.Generator;
            }
            elseif ($lld.invokation -eq [Invokation]::LOCAL) {
                $metrics = $lld.Generator.InvokeReturnAsIs($script);
            }
            $lldTemplateScript = $lld.GenerateByMetrics($metrics);
            $additionalText += $lldTemplateScript + [System.Environment]::NewLine;
            $templateGroupBody += ("`$this.templates.Add(`$this.templates.Count,[" + $lld.ClassName + "]::new(`$this));`r`n`t");
        }

        $script.Body = $script.Body.Replace("<templateGroupBody>",$templateGroupBody);
    }
    else { $script.body = $script.Body.Replace("<templateGroupBody>","");  }

    [string]$runtimePath = [System.IO.Path]::Combine($targetPath,"RuntimeHosts",$script.className + ".psm1");
    
    $usingModulesString = "using module $PSScriptRoot\CoreLibrary.psm1;$([System.Environment]::NewLine)";

    foreach ($el in $script.Templates) {
        $usingModulesString += "using module $targetPath\RuntimeTemplates\$el.psm1;$([System.Environment]::NewLine)";
    }

    $script.body = $usingModulesString + $additionalText + $script.body;

    try { #testing scripts
        Invoke-Expression -Command $script.body;
    } catch {
        Write-Host -Object ($script.body)
        $_
    }

    SetContent $runtimePath $script.body;

    $hosts.Add(
    @{
        HostName=$hostName;
        Body = $script.body;
    });
}

Set-Location $initialLocation;

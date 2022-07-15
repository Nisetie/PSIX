# --- INCLUDE
using module .\CoreLibrary.psm1

# --- INITIALIZATION

cls;

$initialLocation = Get-Location;
Set-Location $PSScriptRoot;

[bool]$DEBUG = $true;

if (test-path "$PSScriptRoot\RuntimeHosts") {
	Get-ChildItem -Path "$PSScriptRoot\RuntimeHosts" | %{ $_.Delete(); }
} else {
	New-Item -Path "$PSScriptRoot\RuntimeHosts" -ItemType Directory | out-null
}

if (test-path "$PSScriptRoot\RuntimeTemplates") {
	Get-ChildItem -Path "$PSScriptRoot\RuntimeTemplates" | %{ $_.Delete(); }
} else {
	New-Item -Path "$PSScriptRoot\RuntimeTemplates" -ItemType Directory | out-null
}

$hostGroups = New-Object "System.Collections.Generic.Dictionary[string,[System.Collections.Generic.List[object]]]";
$hosts = New-Object "System.Collections.Generic.List[object]";
$templates = New-Object "System.Collections.Generic.List[object]";

# STEP 1. TEMPLATES. SCAN.
Write-Host "Search for templates. Begin..." -ForegroundColor Black -BackgroundColor Green;

Set-Location .\Templates;

Write-Host "Search for templates. Template: " (Get-Location).ToString();

$templatesCatalog = Get-ChildItem  -Directory;

Write-Host ("Search for templates. End. " + $templatesCatalog.Length.ToString() + " templates...");

# STEP 2. TEMPLATES. PARSE.
foreach ($template in $templatesCatalog) {

    if ($template.BaseName[0] -eq '#') {
        continue;
    }

    $script = ParseTemplateCatalog $template.FullName; 

    try {
        Invoke-Expression -Command $script.body;
    } catch {
        Write-Host -Object ($script.body)
        $_
    }

    [string]$path = $PSScriptRoot + "\RuntimeTemplates\" + $template.BaseName + ".psm1";

    $usingModulesString = "using module $PSScriptRoot\CoreLibrary.psm1;`r`n";

    Set-Content `
        -Path ($path)`
        -Value ($usingModulesString + $script.body);

    $templates.Add(
    @{
        TemplateName=$template.BaseName;
        Body = $script.body
    });
}


# STEP 3. HOSTS GROUPS. SCAN.
Write-Host "Search for hosts groups. Begin..." -ForegroundColor Black -BackgroundColor Green;

Set-Location ($PSScriptRoot + "\HostGroups");

Write-Host "Search for hosts groups. Group: " (Get-Location).ToString();

$hostGroupCatalogs = Get-ChildItem -Directory;

Write-Host ("Search for hosts groups. End. " + $hostGroupCatalogs.Length.ToString() + " groups...");

# STEP 4. HOSTS GROUPS. PARSE.
foreach ($hostGroupCatalog in $hostGroupCatalogs) {

    if ($hostGroupCatalog.BaseName[0] -eq '#') {
        continue;
    }

    Write-Host ("Обработка группы хостов " + $hostGroupCatalog.ToString());

    $llds = new-object 'System.Collections.Generic.List[object]';
    if (test-path "$($hostGroupCatalog.FullName)\LLDs") {
        $lldsDirs = Get-ChildItem -Path ("$($hostGroupCatalog.FullName)\LLDs") -Directory;
        foreach ($lldDir in $lldsDirs) {
            $llds.Add((ParseLLDCatalog -path $lldDir.FullName));
        }
    }

    $hostsListFile = Get-ChildItem -Path $hostGroupCatalog -File -Filter "hosts.txt";
    if ($hostsListFile.Count -eq 0) { continue; }
    $hostsList = Get-Content -Path $hostsListFile.FullName;

    $templatesListFile = Get-ChildItem -Path $hostGroupCatalog -File -Filter "templates.txt";
    if ($templatesListFile.Count -eq 0) { $templatesList = $null; }
    else { $templatesList = Get-Content -Path $templatesListFile.FullName; }

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
                continue; #if not exitst
            }
            if ($template -ne [string]::Empty -and $hostGroups[$hostName][0].Contains($template) -eq $false) {
                $hostGroups[$hostName][0].Add($template)
            }
        }
    }
}

# Сформировать перечень хостов и их составов
Write-Host "Поиск хостов. Начало..." -ForegroundColor Black -BackgroundColor Green;

Set-Location ($PSScriptRoot + "\Hosts");

Write-Host ("Поиск хостов. Каталог: " + (Get-Location).ToString());

$hostCatalogs = Get-ChildItem -Directory

Write-Host ("Поиск каталогов описаний хостов. Найдено " + $hostCatalogs.Length.ToString() + " хостов...");

foreach ($remoteHost in $hostCatalogs) {

    if ($remoteHost.BaseName[0] -eq '#') {
        continue;
    }

    $hostName = $remoteHost.BaseName;

    $script = ParseHostCatalog $remoteHost.FullName; 

    $additionalText = '';
    
    if ($hostGroups.ContainsKey($remoteHost.BaseName.ToLower()) -eq $true) {

        $templatesList = $hostGroups[$remoteHost.BaseName.ToLower()][0];
        $templateGroupBody = "";
        foreach ($template in $templatesList) {
            if ($script.Templates.Contains($template) -eq $false) {
                $script.Templates.Add($template);
            }
            $templateGroupBody += ("`$this.templates.Add([" + $template + "]::new(`$this));`r`n`t");
        }

        #$templateGroupBody += $hostGroups[$remoteHost.BaseName.ToLower()][1].Replace("<hostName>",$hostName);;
        $llds = $hostGroups[$remoteHost.BaseName.ToLower()][1];
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
            $templateGroupBody += ("`$this.templates.Add([" + $lld.ClassName + "]::new(`$this));`r`n`t");
                
        }

        $script.Body = $script.Body.Replace("<templateGroupBody>",$templateGroupBody);
    }
    else { $script.body = $script.Body.Replace("<templateGroupBody>","");  }

    [string]$path = $PSScriptRoot + "\RuntimeHosts\" + $hostName + ".psm1";
    
    $usingModulesString = "using module $PSScriptRoot\CoreLibrary.psm1;`r`n";

    foreach ($el in $script.Templates) {
        $usingModulesString += "using module $PSScriptRoot\RuntimeTemplates\$el.psm1;`r`n";
    }

    $script.body = $usingModulesString + $additionalText + $script.body;

    try {
        Invoke-Expression -Command $script.body;
    } catch {
        Write-Host -Object ($script.body)
        $_
    }

    Set-Content `
        -Path ($path)`
        -Value ($script.body);

    $hosts.Add(
    @{
        HostName=$hostName;
        Body = $script.body;
    });
}

Set-Location $initialLocation;

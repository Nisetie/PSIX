# --- INCLUDE
using module .\CoreLibrary.psm1

# --- INITIALIZATION

cls;

Set-Location $PSScriptRoot;

[bool]$DEBUG = $true;

if (test-path "$PSScriptRoot\RuntimeHosts") {
	Get-ChildItem -Path "$PSScriptRoot\RuntimeHosts" | ? { $_.Delete(); }
} else {
	New-Item -Path "$PSScriptRoot\RuntimeHosts" -ItemType Directory | out-null
}

if (test-path "$PSScriptRoot\RuntimeTemplates") {
	Get-ChildItem -Path "$PSScriptRoot\RuntimeTemplates" | ? { $_.Delete(); }
} else {
	New-Item -Path "$PSScriptRoot\RuntimeTemplates" -ItemType Directory | out-null
}

$hostGroups = New-Object "System.Collections.Generic.Dictionary[string,[System.Collections.Generic.List[object]]]";
$hosts = New-Object "System.Collections.Generic.List[object]";
$templates = New-Object "System.Collections.Generic.List[object]";

# Сформировать перечень шаблонов и определения их составов
Write-Host "Поиск шаблонов. Начало..." -ForegroundColor Black -BackgroundColor Green;

Set-Location .\Templates;

Write-Host "Поиск шаблонов. Каталог: " (Get-Location).ToString();

$templatesCatalog = Get-ChildItem  -Directory;

Write-Host ("Поиск шаблонов. Найдено " + $templatesCatalog.Length.ToString() + " шаблонов...");

# Генерация и выполнение скриптов на основании содержания текстовых файлов
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


# Поиск груп хостов с одинаковыми шаблонами
Write-Host "Поиск групп хостов. Начало..." -ForegroundColor Black -BackgroundColor Green;

Set-Location ($PSScriptRoot + "\HostGroups");

Write-Host "Поиск групп хостов. Каталог: " (Get-Location).ToString();

$hostGroupCatalogs = Get-ChildItem -Directory;

Write-Host ("Поиск групп хостов. Найдено " + $hostGroupCatalogs.Length.ToString() + " шаблонов...");

foreach ($hostGroupCatalog in $hostGroupCatalogs) {

    if ($hostGroupCatalog.BaseName[0] -eq '#') {
        continue;
    }

    Write-Host ("Обработка группы хостов " + $hostGroupCatalog.ToString());

    $hostsListFile = Get-ChildItem -Path $hostGroupCatalog -File -Filter "hosts.txt";
    if ($hostsListFile.Count -eq 0) { continue; }
    $hostsList = Get-Content -Path $hostsListFile.FullName;

    $templatesListFile = Get-ChildItem -Path $hostGroupCatalog -File -Filter "templates.txt";
    if ($templatesListFile.Count -eq 0) { continue; }
    $templatesList = Get-Content -Path $templatesListFile.FullName;

    $llds = "";
    if (test-path "$($hostGroupCatalog.FullName)\LLDs") {
        $lldsDirs = Get-ChildItem -Path ("$($hostGroupCatalog.FullName)\LLDs") -Directory;
        foreach ($lldDir in $lldsDirs) {
            $lldBody = (ParseLLDCatalog -path $lldDir.FullName).body;
            $llds += $lldBody;
        }
    }

    foreach ($hostName in $hostsList){    
        $hostName = $hostName.ToLower();
        if ($hostGroups.ContainsKey($hostName) -eq $false) {
            $hostGroups[$hostName] = New-Object "System.Collections.Generic.List[object]";
            $hostGroups[$hostName].Add((New-Object "System.Collections.Generic.List[string]")); #templates
            $hostGroups[$hostName].Add(""); #llds
        }

        $hostGroups[$hostName][1] += $llds;

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
    
    if ($hostGroups.ContainsKey($remoteHost.BaseName.ToLower()) -eq $true) {

        $templatesList = $hostGroups[$remoteHost.BaseName.ToLower()][0];
        $templateGroupBody = "";
        foreach ($template in $templatesList) {
            if ($script.Templates.Contains($template) -eq $false) {
                $script.Templates.Add($template);
            }
            $templateGroupBody += ("`$this.templates.Add([" + $template + "]::new(`$this));`r`n`t");
        }

        $templateGroupBody += $hostGroups[$remoteHost.BaseName.ToLower()][1].Replace("<hostName>",$hostName);;

        $script.Body = $script.Body.Replace("<templateGroupBody>",$templateGroupBody);
    }
    else { $script.body = $script.Body.Replace("<templateGroupBody>","");  }

    [string]$path = $PSScriptRoot + "\RuntimeHosts\" + $hostName + ".psm1";
    
    $usingModulesString = "using module $PSScriptRoot\CoreLibrary.psm1;`r`n";

    foreach ($el in $script.Templates) {
        $usingModulesString += "using module $PSScriptRoot\RuntimeTemplates\$el.psm1;`r`n";
    }

    $script.body = $usingModulesString + $script.body;

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

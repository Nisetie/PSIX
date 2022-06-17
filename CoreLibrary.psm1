Enum ConnectionType { NONE;IP;DNS }

enum GeneratorBlock { EMPTY;TEMPLATE;DEFINE;INIT;UPDATE;GENERATOR }

class MetaModel
{
    [string]$className;
    [System.Collections.Generic.Dictionary[string,int]]$variables;
    [System.Collections.Generic.List[string]]$Templates;
    [System.Collections.Generic.List[LLDInfo]]$llds;
    [string]$body;

    MetaModel()
    {
        $this.variables = [System.Collections.Generic.Dictionary[string,int]]::new();
        $this.Templates = [System.Collections.Generic.List[string]]::new();
    }
}

class LLDInfo
{
    [HostBase]$hostRef;
    [string]$hostName;
    [string]$className;
    [string]$body;
    [scriptblock]$generator;
    [System.Collections.Generic.Dictionary[string,string]]$defines;
    [System.Collections.Generic.Dictionary[string,string]]$inits;
    [System.Collections.Generic.Dictionary[string,System.Array]]$updates;
    [System.Collections.Generic.Dictionary[string,System.Array]]$triggers;

    LLDInfo()
    {
        $this.defines = [System.Collections.Generic.Dictionary[string,object]]::new();
        $this.inits = [System.Collections.Generic.Dictionary[string,object]]::new();
        $this.updates = [System.Collections.Generic.Dictionary[string,object]]::new();
        $this.triggers = [System.Collections.Generic.Dictionary[string,object]]::new();
    }

    [TemplateBase]GenerateByMetrics([object[]]$metrics)
    {
        $result = @"
class <className> : TemplateBase {
    <defineBody>
    <className> ([HostBase]`$h) : base(`$h) {
        <initBody>
    }
}
"@;

        $defineBody = '';
        $initBody = '';
        $updateBody = '';
        $triggerBody = '';

        $initBodyTemplate = @"
`$this.updateScripts.Add(
    @{
        TemplateName = '<templateName>';
        ElementName = '<elementName>';
        CurrentValue = `$null;
        Script = [scriptblock]::create({<updateScript>});
        UpdateTimestamp = [datetime]::MinValue
    });
"@;

        $triggerBodyTemplate = @"
`$triggerInfo = [TriggerInfo]::new();
`$triggerInfo.Script = {<checkScript>};
`$triggerInfo.Host = '<hostName>';
`$triggerInfo.Template = '<templateName>';
`$triggerInfo.Item = '<triggerName>';
`$triggerInfo.DescriptionScript = {return `"<descriptionScript>`"};
`$this.triggers.Add(`$triggerInfo);  
"@;

        $temp = "";

        $templateName = $this.hostName + '_' + $this.className;

        $variables = New-Object 'System.Collections.Generic.Dictionary[string,int]';
        
        for ($i = 0; $i -ne $metrics.Length; ++$i) {
            
            $metricAlias = $metrics[$i].Alias;
            $metricName = $metrics[$i].Name;

            $it = $this.updates.Keys.GetEnumerator();
            while ($it.MoveNext()) {
                $key = $it.Current;
                $temp = $initBodyTemplate;
                $temp = $temp.Replace('<templateName>', $templateName);
                $temp = $temp.Replace('<elementName>', $metricAlias + '_' + $key);
                $variables.Add($metricAlias + '_' + $key, $variables.Count);
                $temp = $temp.Replace('<updateScript>',$this.updates[$key][0].ToString().Replace("`$metric",$metricName));
                $initBody += $temp;
            }
        }

        for ($i = 0; $i -ne $metrics.Length; ++$i) {

            $metricAlias = $metrics[$i].Alias;
            $metricName = $metrics[$i].Name;

            $it = $this.triggers.Keys.GetEnumerator();
            while ($it.MoveNext()) {
                $key = $it.Current;
                $temp = $triggerBodyTemplate;                
              
                $someScript = $this.triggers[$key][0].ToString();                
                $s = ($someScript | Select-String -AllMatches -pattern '\$this.\w*').Matches | select value;
                foreach ($el in $s) { $el = $el.Value; $someScript = ($someScript.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $variables[$metricAlias +'_' + $el.Replace("`$this.","")] + "].CurrentValue"));  }   
                $temp = $temp.Replace('<checkScript>', $someScript);

                $temp = $temp.Replace('<templateName>', $templateName);
                $temp = $temp.Replace('<hostName>', $this.hostName);
                $temp = $temp.Replace('<triggerName>', $metricAlias + '_' + $key);

                $someScript = $this.triggers[$key][1].ToString();                
                $s = ($someScript | Select-String -AllMatches -pattern '\$this.\w*').Matches | select value;
                foreach ($el in $s) { $el = $el.Value; $someScript = ($someScript.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $variables[$metricAlias +'_' + $el.Replace("`$this.","")] + "].CurrentValue"));  }   
                $temp = $temp.Replace('<descriptionScript>', $someScript);

                $initBody += $temp;
            }
        }       

        $result = $result.Replace('<className>', $templateName);
        $result = $result.Replace('<defineBody>', $defineBody); 
        $result = $result.Replace('<initBody>', $initBody); 
        $result = $result.Replace('<updateBody>', $updateBody); 
        $result = $result.Replace('<triggerBody>', $triggerBody); 
        
        Invoke-Expression $result;
        return New-Object -TypeName ($this.hostName + '_' + $this.className) -ArgumentList ($this.hostRef);
    }
}

class TriggerInfo
{
    [string]$Host;
    [string]$Template;
    [string]$Item;
    [bool]$Status;
    [scriptblock] $Script;
    [scriptblock] $DescriptionScript;
    [string] $Description;
}

class HostBase
{
	[timespan]$UpdateDelta;
    [timespan]$UpdateDeltaTemplates;
	[timespan]$UpdateDeltaTotal;
    [ConnectionType]$connectionType;
    [string]$FQDN;
    [string]$ip;
    [object]$ping;
    [string]$hostName;
    [System.Collections.Generic.List[TemplateBase]]$templates;
    [System.Collections.Generic.List[hashtable]]$updateScripts;
    [System.Collections.Generic.List[TriggerInfo]]$triggers;
    [System.Collections.Generic.List[LLDInfo]]$llds;
    [bool]$firstUpdate;
    #[object]$session;
    [System.Collections.ArrayList]$us;
    [object]$checked;

    HostBase([string]$hostN) {
        $this.hostName = $hostN;
        $this.templates = [System.Collections.Generic.List[TemplateBase]]::new();
        $this.updateScripts = [System.Collections.Generic.List[hashtable]]::new();
        $this.triggers = [System.Collections.Generic.List[TriggerInfo]]::new();
        $this.llds =  [System.Collections.Generic.List[LLDInfo]]::new();
        $this.firstUpdate = $true;

        $this.CheckPing();
        $this.CheckHost();
    }

    [string]ConnectionAddress() {
        #if ($this.connectionType -eq [ConnectionType]::IP) { return $this.ip; }
        #else { return $this.hostName; }
        return $this.hostName;
    }

    [System.Array]GetUpdateScripts()
    {
        $en = $this.updateScripts.GetEnumerator();
        $ar = New-Object 'System.Collections.ArrayList';
        $curr = $null;
        while ($en.MoveNext()) {
            $curr = $en.Current;
            #if (([datetime]::Now - $curr.UpdateTimestamp).Seconds -ge $curr.UpdateInterval) {
                #$curr.UpdateTimestamp = [datetime]::Now;
                [void]$ar.Add($curr);                
            #}
        }

        return $ar;
    }

    [void]CheckHost() {
        # Первичная проверка хоста
        try {
            $this.FQDN = [System.Net.Dns]::GetHostByName($this.hostname).Hostname;
            $this.ip = [System.Net.Dns]::GetHostByName($this.hostname).AddressList[0].IPAddressToString;
        }
        catch {
            $this.ip = $null;
            $this.ping = $null;
        }
    }

    # Формирование скриптов для выполнения на стороне хоста
    [void]InitializeData([string[]]$tFilter = $null) {    
        
        $this.us = [System.Collections.ArrayList]::new();

        if ($this.ping -ne $null) {
            #LLD
            for ([int]$i = 0; $i -lt $this.LLDs.Count; ++$i)  {
                $lld = $this.LLDs[$i];
                $metrics = Invoke-Command -ComputerName ($this.hostName) -scriptblock  $lld.Generator;
                $this.templates.Add($lld.GenerateByMetrics($metrics));
            }
        }

        [void]$this.us.Add( # Скрипты данного хоста
            @{
                id = -1;
                updates = $this.GetUpdateScripts();
                updateDelta = [timespan]::Zero;
            }
        );

        # Filter of templates
        if ($tFilter -ne $null) {
            for ([int]$i = 0; $i -lt $this.templates.Count; ++$i)  {
                $toRemove = $true;
                foreach ($fTemplate in $tFilter) {            
                    if ($this.templates[$i].templateName -eq $fTemplate) {
                        $toRemove = $false;
                        break;
                    }
                }
                if ($toRemove) {
                    $this.templates.RemoveAt($i);
                    $i--;
                }
            
            }
        }

        # Скрипты вложенных шаблонов
        for ([int]$i = 0; $i -lt $this.templates.Count; ++$i) {
            $t = $this.templates[$i];

            [void]$this.us.Add(
                @{ 
                    id = $i;
                    updates = $t.GetUpdateScripts();
                    updateDelta = [timespan]::Zero;
                }
            );
        }
    }

    [void]CheckPing() {
        $this.ping = ((Test-Connection -ComputerName ($this.hostName) -Count 1 -ErrorAction SilentlyContinue).ResponseTime)
    }

    [void]Update()  
    {
        $this.UpdateDeltaTotal = [timespan]::Zero;
        $this.UpdateDeltaTemplates = [timespan]::Zero;

        $this.CheckPing();
        if ($this.ping -eq $null) { return; }

        if ($this.firstUpdate -eq $true) {           
            $this.firstUpdate = $false;
        }        

        $uss = Invoke-Command -ComputerName ($this.hostName) -SessionOption (New-PSSessionOption -NoCompression -NoMachineProfile -IdleTimeout 300000) -ScriptBlock {
            param([object]$us)
            $UpdateScripts = $us.us; # Надо так. Иначе не захватывается почему-то вся передаваемая коллекция скриптов обновлений
            $UpdateScriptsCount = $UpdateScripts.Count;
            
            $scriptBlockArgs = @();
            $ssw = New-Object 'System.Diagnostics.Stopwatch';
            for ([int]$i = 0; $i -lt $UpdateScriptsCount; ++$i) {
                $UpdateScript = $UpdateScripts[$i];
                $updates = $UpdateScript.updates;
                $scriptsCount = $updates.Count;                
                $ssw.Restart();
                for ([int]$j = 0; $j -lt $scriptsCount; ++$j) {
                    $update = $updates[$j];         
                    # Invoke-Expression makes an irrational shit. Don't use it.	
                    $update.CurrentValue = [scriptblock]::Create('try { ' + $update.Script + ' } catch { $_ | select CategoryInfo,ErrorDetails | Out-String  }').InvokeReturnAsIs($null);
                }
                $UpdateScript.UpdateDelta = $ssw.Elapsed;
            }
            $ssw.Stop();            

            return $UpdateScripts;
            
        } -ArgumentList @{us=$this.us};

        if ($uss -eq $null){ return; }
        
        # Получение обновленных данных данного хоста
        if ($uss -is [array]){
            $this.us = $uss;
            #$this.us | Sort-Object -Property id;
            $updateScript = $this.us[0].updates;
            if ($this.us[0].updateDelta -ne $null) {$this.UpdateDelta = $this.us[0].updateDelta}
        }
        else {              
            $updateScript = $uss.updates;
            if ($uss.updateDelta -ne $null) {$this.UpdateDelta = $uss.updateDelta}
        }
        for ([int]$j = 0; $j -lt $updateScript.Count; ++$j) {
            $this.updateScripts[$j] = $updateScript[$j];
        }

        
        # Получение обновленных данных вложенных шаблонов
        if ($this.us -is [System.Collections.ArrayList]) {
            $usc = $this.us.Count;
            for ([int]$i = 1; $i -lt $usc; ++$i) 
            {
                $id = $this.us[$i].id;
                $updateScript = $this.us[$i].updates;
                $t = $this.templates[$id];
                $t.UpdateDelta = $this.us[$i].updateDelta;
                $this.UpdateDeltaTemplates += $this.us[$i].updateDelta;
                $this.UpdateDeltaTotal += $this.us[$i].updateDelta;
                $upc = $updateScript.Count;
                for ([int]$j = 0; $j -lt $upc; ++$j) {
                    $t.updateScripts[$j] = $updateScript[$j];
                }
            }
        }        

        $this.UpdateDeltaTotal += $this.updateDelta;
    }

    [void]Check()
    {
        $result = [System.Collections.Generic.List[TriggerInfo]]::new();

        $pingTrigger = [TriggerInfo]::new();
        $pingTrigger.Host = $this.hostName;
        $pingTrigger.Template = '';
        $pingTrigger.Item = "ping";
        $pingTrigger.Description = {return "PING FAIL! " + $args[0].hostName.ToString()}.Invoke($this);
        if ($this.ping -eq $null)
        {
            $pingTrigger.Status = $true;
        } else { 
            $pingTrigger.Status = $false;
        }

        $result.Add($pingTrigger);

	    if ($this.ping -ne $null) {
            for ($i = 0; $i -ne $this.triggers.Count; ++$i) {
                $triggerInfo = $this.triggers[$i];
                $triggerInfo.Status = ($triggerInfo.Script.Invoke($this) -eq $true);
                $triggerInfo.Description = $triggerInfo.DescriptionScript.Invoke($this);
            }

            $result.AddRange($this.triggers);

            for ([int]$i = 0; $i -lt $this.templates.Count; ++$i) 
            {
                $templateResult = $this.templates[$i].GetTriggers();
                $result.AddRange($templateResult);
            }
        }

        $this.Checked = $result;
    }    
}

class TemplateBase
{
	[timespan]$UpdateDelta;
    [string]$templateName;
    [object]$hostRef;
    [System.Collections.Generic.List[hashtable]]$updateScripts;
    [System.Collections.Generic.List[TriggerInfo]]$triggers;

    TemplateBase([object]$hostReference)
    {
        $this.hostRef = $hostReference;
        $this.templateName = $this.GetType().Name;
        $this.updateScripts = [System.Collections.Generic.List[hashtable]]::new();
        $this.triggers = [System.Collections.Generic.List[TriggerInfo]]::new();
    }

    [void]Update()
    {

    }

    [System.Array]GetUpdateScripts()
    {
        $en = $this.updateScripts.GetEnumerator();
        $ar = New-Object 'System.Collections.ArrayList';
        $curr = $null;
        while ($en.MoveNext()) {
            $curr = $en.Current;
            if (([datetime]::Now - $curr.UpdateTimestamp).Seconds -ge $curr.UpdateInterval) {
                $curr.UpdateTimestamp = [datetime]::Now;
                [void]$ar.Add($curr);                
            }
        }

        return $ar;
    }

    [TriggerInfo[]]GetTriggers()
    {
        for ($i = 0; $i -ne $this.triggers.Count; ++$i) {
            $triggerInfo = $this.triggers[$i];
            $triggerInfo.Status = ($triggerInfo.Script.Invoke($this) -eq $true);
            $triggerInfo.Description = $triggerInfo.DescriptionScript.Invoke($this);
        }
        return $this.triggers;
    }
}

function ParseUpdatesCatalog([MetaModel]$info,[string]$className,[string]$path) {
    $updates = Get-ChildItem -Path $path -File -Filter "*.txt";
    $id = 0;
    $initBody = '';
    for ($i = 0; $i -ne $updates.Count; ++$i) {
        $updateFile = $updates[$i];
        if ($updateFile.BaseName[0] -eq '#') {continue;}

	    $updateFileParts = $updateFile.BaseName.Split(" ");
        if ($updateFile.Basename -match '\s\d*\s*') {
            $updateIntervalElement = [int]::Parse($Matches.Values[0].Trim());
        } else { 
            $updateIntervalElement = 1;
        }
        if ($updateFile.Basename -match '\slocal\s*') {
            $isLocal = $true;
        } else {
            $isLocal = $false;
        }
        $scriptText = (Get-Content -Path $updateFile.FullName -Raw);
        $initBody += "`$this.updateScripts.Add(
        @{
            TemplateName = `"$className`";
            ElementName = `"$($updateFile.BaseName)`";
            CurrentValue = `$null;
            Script = [scriptblock]::create({"+ $scriptText + "});
            UpdateInterval = $($updateIntervalElement.ToString());
            UpdateTimestamp = [datetime]::MinValue;
            IsLocal = `$$isLocal;
            Exception = [string]::Empty;
        });
        ";
        $info.variables.Add($updateFile.BaseName, $id);
        ++$id;
    }
    return $initBody;
}

function ParseTriggersCatalog([MetaModel]$info,[string]$path) {
    $triggers = Get-ChildItem -Path ($path) -Directory;
    $initBody = '';
    for ($i = 0; $i -ne $triggers.Count; ++$i) {
        if ($triggers[$i].BaseName[0] -eq '#') {continue;}

        $triggerCatalog = $triggers[$i];
        $triggerItemName = $triggerCatalog.BaseName.trim(); 
        if ($triggerItemName[0] -eq '#') { continue; }
        if ((Test-Path -Path ($triggerCatalog.Fullname + "\check.txt")) -eq $false) { continue; } 
        $triggerScript = Get-Content -Path ($triggerCatalog.Fullname + "\check.txt") -Raw;
        $triggerDescription = $triggerItemName + "!";
        if ((Test-Path -Path ($triggerCatalog.Fullname + "\message.txt")) -eq $true) {
            $triggerDescription = Get-Content -Path ($triggerCatalog.Fullname + "\message.txt") -Raw;
        }
        $s = ($triggerScript | Select-String -AllMatches -pattern '\$this.\w*').Matches | select value;
        foreach ($el in $s) { $el = $el.Value; $triggerScript = ($triggerScript.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $info.variables[$el.Replace("`$this.","")] + "].CurrentValue"));  }   
        $s = ($triggerDescription | Select-String -AllMatches -pattern '\$this.\w*').Matches | select value;
        foreach ($el in $s) { $el = $el.Value; $triggerDescription = ($triggerDescription.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $info.variables[$el.Replace("`$this.","")] + "].CurrentValue"));  }      
        $initBody += @"
`$triggerInfo = [TriggerInfo]::new();
`$triggerInfo.Script = {$triggerScript};
`$triggerInfo.Host = '$($info.ClassName)';
`$triggerInfo.Template = `$this.TemplateName;
`$triggerInfo.Item = '$triggerItemName';
`$triggerInfo.DescriptionScript = {return `"$triggerDescription`"};
`$this.triggers.Add(`$triggerInfo);  
"@;
    }
    return $initBody;
}

function ParseTemplateCatalog ([string] $path) {

    [int]$updateIntervalDefault = 1;

    if ((Test-Path -Path $path) -eq $false) {
        return [string[]]::new(0);
    }

    $className = (Get-Item -Path $path).Name;
    
    [MetaModel] $templateInfo = [MetaModel]::new();
    $templateInfo.className = $className;

    $body = 
"class <className> : TemplateBase {
    <defineBody>
    <className> ([object]`$hostReference) : base(`$hostReference) {
        <initBody>
    }
    [void]Update() {
        ([TemplateBase]`$this).Update();
        <updateBody>
    }
}";
   
    $templateBody = "";
    $defineBody = "";
    $initBody = "";
    $updateBody = "";
    $triggerBody = "";

    $defineRows = [System.Collections.Generic.List[object]]::new();
    $UpdateRows = [System.Collections.Generic.List[object]]::new();    

    if ([System.IO.Directory]::Exists($path + "\updates") -eq $true) {        
        $initBody += ParseUpdatesCatalog $templateInfo $className ($path + "\updates")
    }
    if ([System.IO.Directory]::Exists($path + "\triggers") -eq $true) {   
        $initBody += ParseTriggersCatalog $templateInfo ($path + "\triggers")
    }

    $body = $body.Replace("<className>",$className);
    $body = $body.Replace("<templateBody>",$templateBody); 
    $body = $body.Replace("<defineBody>",$defineBody); 
    $body = $body.Replace("<initBody>",$initBody); 
    $body = $body.Replace("<updateBody>",$updateBody); 
    $body = $body.Replace("<triggerBody>",$triggerBody);

    $templateInfo.body = $body;

    return $templateInfo;
}

function ParseHostCatalog ([string] $path) {

    [int]$updateIntervalDefault = 1;

    if ((Test-Path -Path $path) -eq $false) {
        return [string[]]::new(0);
    }

    $className = (Get-Item -Path $path).Name;

    [MetaModel] $hostInfo = [MetaModel]::new();
    $hostInfo.className = $className;

    $body = 
"class <className> : HostBase {
    <defineBody>
`t" + $className + "() : base('$className') {
        <initBody>
        <templateBody>
        <templateGroupBody>
    }
    
    [void]Update() {
        ([HostBase]`$this).Update();
        <updateBody>
    }
}";

    $templateBody = "";
    $defineBody = "";
    $initBody = "";
    $updateBody = "";
    $triggerBody = "";    

    $defineRows = [System.Collections.Generic.List[object]]::new();
    $UpdateRows = [System.Collections.Generic.List[object]]::new();

    
    if ([System.IO.File]::Exists($path + "\templates.txt") -eq $true) {            
        $rows = (Get-Content ($path + "\templates.txt"));
        foreach($row in $rows) {
            if ($row -eq "" -or $row[0] -eq "#") { continue; }
            $templateBody += ("`$this.templates.Add([" + $row.Trim() + "]::new(`$this));`r`n");
            $hostInfo.Templates.Add($row.Trim());
        }
    }
    if ([System.IO.Directory]::Exists($path + "\updates") -eq $true) {        
        $initBody += ParseUpdatesCatalog $hostInfo $className ($path + "\updates")
    }
    if ([System.IO.Directory]::Exists($path + "\triggers") -eq $true) {   
        $initBody += ParseTriggersCatalog $hostInfo ($path + "\triggers")
    }
    if ([System.IO.Directory]::Exists($path + "\llds") -eq $true) {        
        $llds = Get-ChildItem -Path ($path + "\llds") -Directory;
        foreach ($lld in $llds) {
            $lldInfo = ParseLLDCatalog($path + "\llds\" + $lld.Name);
            $initBody += $lldInfo.body.Replace("<hostName>",$className);
        }
    }

    $body = $body.Replace("<className>",$className);
    $body = $body.Replace("<templateBody>",$templateBody); 
    $body = $body.Replace("<defineBody>",$defineBody); 
    $body = $body.Replace("<initBody>",$initBody); 
    $body = $body.Replace("<updateBody>",$updateBody); 
    $body = $body.Replace("<triggerBody>",$triggerBody);

    $hostInfo.body = $body;

    return $hostInfo;
}

function ParseLLDCatalog ([string] $path) {

    $body = "`$lld = [LLDInfo]::new();`n"
    $body += "`$lld.hostRef = `$this`n";
    $body += "`$lld.hostName = `"<hostName>`"`n";
    
    [int]$updateIntervalDefault = 1;

    if ((Test-Path -Path $path) -eq $false) {
        return [string[]]::new(0);
    }

    $className = (Get-Item -Path $path).Name;

    $body += "`$lld.className = `"$Classname`"`n";

    $files = Get-ChildItem -Path $path -File;
   
    $defineBody = "";
    $initBody = "";
    $updateBody = "";
    $triggerBody = "";

    $defineRows = [System.Collections.Generic.List[object]]::new();
    $UpdateRows = [System.Collections.Generic.List[object]]::new();

    [LLDInfo] $lldInfo = [LLDInfo]::new();

    [GeneratorBlock]$block = [GeneratorBlock]::TEMPLATE;

    foreach($file in $files) {
        
        if ($file.Basename[0] -eq '#') {continue;}

        if ($file.BaseName.ToLower() -eq "defines") { $block = [GeneratorBlock]::DEFINE; } 
        elseif ($file.BaseName.ToLower() -eq "generator") { $block = [GeneratorBlock]::GENERATOR; } 
        else { continue; }

        if ($block -eq [GeneratorBlock]::DEFINE) {

            $rows = (Get-Content $file.FullName);

            foreach($row in $rows) {
                if ($row -eq "" -or $row[0] -eq "#") { continue; }            
                $varDetails = $row.Split(" ");                
                #$lldBody.variables.Add(@{ Type =  $varDetails[0]; Name =  $varDetails[1] });                        
                $body += "`$lld.defines.Add($($varDetails[1]),$($varDetails[0]))`n";
            }
        }
        elseif ($block -eq [GeneratorBlock]::GENERATOR) {
            #$lldInfo.generator = [scriptblock]::Create(Get-Content $file.FullName -Raw);
            $body += "`$lld.generator = {$(Get-Content $file.FullName -Raw)}`n";
        }
    }
    if ([System.IO.Directory]::Exists($path + "\updates") -eq $true) {        
        $updates = Get-ChildItem -Path ($path + "\updates") -File;
        foreach ($updateFile in $updates) {
            if ($updateFile.BaseName[0] -eq '#') {continue;}

            $updateFileParts = $updateFile.BaseName.Split(" ");
            if ($defineBody -match ($updateFileParts[0] + "[^a-f\d]") -eq $false) { 
                #$lldInfo.defines.Add("`"$updateFileParts[0]`"",'object');   
                $body += "`$lld.defines.Add(`"$($updateFileParts[0])`",'object')`n";
            }
            $updateIntervalElement = $updateIntervalDefault;
            if ($updateFileParts.Length -ge 2) {$updateIntervalElement = [int]::Parse($updateFileParts[1]);}
            $scriptText = (Get-Content -Path $updateFile.FullName -Raw);
            #$lldInfo.updates.Add($updateFileParts[0], @($scriptText,$updateIntervalElement));
            $body += "`$lld.updates.Add(`"$($updateFileParts[0])`",@({$scriptText},$updateIntervalElement));`n";
        }
    }    
    if ([System.IO.Directory]::Exists($path + "\triggers") -eq $true) {        
        $triggers = Get-ChildItem -Path ($path + "\triggers") -Directory;
        foreach ($triggerCatalog in $triggers) {
            $triggerItemName = $triggerCatalog.BaseName; 
            if ($triggerItemName[0] -eq '#') { continue; }
            if ((Test-Path -Path ($triggerCatalog.Fullname + "\check.txt")) -eq $false) { continue; } 
            $triggerScript = Get-Content -Path ($triggerCatalog.Fullname + "\check.txt") -Raw;
            $triggerDescription = $triggerItemName + "!";
            if ((Test-Path -Path ($triggerCatalog.Fullname + "\message.txt")) -eq $true) {$triggerDescription = Get-Content -Path ($triggerCatalog.Fullname + "\message.txt") -Raw;}
            #$lldInfo.triggers.Add( $triggerItemName,$triggerScript);
            $body += "`$lld.triggers.Add(`"$triggerItemName`",@({$triggerScript},`"$triggerDescription`"));`n";
        }
    }

    $body += "`$this.llds.Add(`$lld);`n";        


    $lldInfo.className = $className;

    $lldInfo.body = $body;

    return $lldInfo;
}
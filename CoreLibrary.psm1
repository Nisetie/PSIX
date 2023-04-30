Enum ConnectionType { NONE;IP;DNS }

enum GeneratorBlock { EMPTY;TEMPLATE;DEFINE;INIT;UPDATE;GENERATOR }

enum ObjectType {HOST; TEMPLATE}
enum Invokation {REMOTE; LOCAL}

class MetaModel
{
    [ObjectType]$objectType;
    [string]$className;
    [object]$tag;
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
    [System.Collections.Generic.Dictionary[string,string]]$updates;
    [System.Collections.Generic.Dictionary[string,System.Array]]$triggers;
    [Invokation] $invokation;

    LLDInfo()
    {
        $this.defines = [System.Collections.Generic.Dictionary[string,object]]::new();
        $this.inits = [System.Collections.Generic.Dictionary[string,object]]::new();
        $this.updates = [System.Collections.Generic.Dictionary[string,object]]::new();
        $this.triggers = [System.Collections.Generic.Dictionary[string,object]]::new();
    }

    [string]GenerateByMetrics([object[]]$metrics)
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
`$triggerInfo.Host = <hostName>;
`$triggerInfo.Template = '<templateName>';
`$triggerInfo.Item = '<triggerName>';
`$triggerInfo.DescriptionScript = {return `"<descriptionScript>`"};
`$this.triggers.Add(`$triggerInfo);  
"@;

        $temp = ""; # filler for final definition of LLD-class

        $templateName = $this.className;

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
                $temp = $temp.Replace('<updateScript>',$this.updates[$key].ToString().Replace('$metric',"'"+$metricName.Replace('''','''''')+"'"));
                $initBody += $temp + [System.Environment]::NewLine;
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
                foreach ($el in $s) { 
                    $el = $el.Value; 
                    $someScript = ($someScript.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $variables[$metricAlias +'_' + $el.Replace("`$this.","")] + "].CurrentValue"));  
                }   

                $temp = $temp.Replace('<checkScript>', $someScript);
                $temp = $temp.Replace('<templateName>', $templateName);
                $temp = $temp.Replace('<hostName>', '$this.HostRef.HostName');
                $temp = $temp.Replace('<triggerName>', $metricAlias + '_' + $key);

                $someScript = $this.triggers[$key][1].ToString();                
                $s = ($someScript | Select-String -AllMatches -pattern '\$this.\w*').Matches | select value;
                foreach ($el in $s) {
                    $el = $el.Value;
                    $someScript = ($someScript.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $variables[$metricAlias +'_' + $el.Replace("`$this.","")] + "].CurrentValue")); 
                }   

                $temp = $temp.Replace('<descriptionScript>', $someScript);

                $initBody += $temp + [System.Environment]::NewLine;
            }
        }       

        $result = $result.Replace('<className>', $templateName);
        $result = $result.Replace('<defineBody>', $defineBody); 
        $result = $result.Replace('<initBody>', $initBody); 
        $result = $result.Replace('<updateBody>', $updateBody); 
        $result = $result.Replace('<triggerBody>', $triggerBody); 
        
        return $result;
    }

    [TemplateBase]GenerateType([scriptblock]$scr)
    {
        Invoke-Expression $scr;
        return New-Object -TypeName ($this.className) -ArgumentList ($this.hostRef);
    }

    [TemplateBase]GenerateTypeByMetrics([object[]]$metrics)
    {        
        Invoke-Expression ($this.GenerateByMetrics($metrics));
        return New-Object -TypeName ($this.className) -ArgumentList ($this.hostRef);
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
    [string] $Description; # buffer for $DescriptionScript's result

    [void]Check([object]$node){
        $this.Status = ($this.Script.Invoke($node) -eq $true);
        $this.Description = $this.DescriptionScript.Invoke($node);
    }
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
	[string]$address;
    [System.Collections.Generic.List[TemplateBase]]$templates;
    [System.Collections.Generic.List[hashtable]]$updateScripts;
    [System.Collections.Generic.List[TriggerInfo]]$triggers;
    [System.Collections.Generic.List[LLDInfo]]$llds;
    [System.Collections.ArrayList]$us;
    [object]$checked;

    HostBase([string]$hostN,[string]$address) {
        $this.hostName = $hostN;
	$this.address = $address;
        $this.templates = [System.Collections.Generic.List[TemplateBase]]::new();
        $this.updateScripts = [System.Collections.Generic.List[hashtable]]::new();
        $this.triggers = [System.Collections.Generic.List[TriggerInfo]]::new();
        $this.llds =  [System.Collections.Generic.List[LLDInfo]]::new();
    }

    [string]ConnectionAddress() {
        return $this.address;
    }

    [System.Array]GetUpdateScripts()
    {
        return $this.updateScripts.ToArray();
    }

    [void]CheckHost() {
        try {
		    if ($this.connectionType -eq [connectionType]::DNS) {
			    $this.FQDN = [System.Net.Dns]::GetHostByName($this.address).Hostname;
			    $this.ip = [System.Net.Dns]::GetHostByName($this.address).AddressList[0].IPAddressToString;
		    } else {
			    $this.FQDN = [System.Net.Dns]::GetHostByAddress($this.address).Hostname;
			    $this.ip = $this.address;		
		    }
        } catch {
            $this.ip = $null;
            $this.ping = $null;
        }
    }

    # Формирование скриптов для выполнения на стороне хоста
    [void]InitializeData([string[]]$tFilter = $null,[string[]]$tiFilter = $null) {    
         
        $this.CheckPing();
        $this.CheckHost();

        $this.us = [System.Collections.ArrayList]::new();

        [void]$this.us.Add( # Скрипты данного хоста
            @{
                id = -1;
                updates = $this.GetUpdateScripts();
                updateDelta = [timespan]::Zero;
            }
        );

        # Filtering
        if ($tFilter -ne $null) { #inlcude
            for ($i = 0; $i -lt $this.templates.Count; ++$i)  {
                $toRemove = $true;
                if ($tFilter -contains $this.templates[$i].templateName) {
                        $toRemove = $false;
                   }
                
                if ($toRemove) {
                    $this.templates.RemoveAt($i);
                    $i--;
                }
            
            }
        }
        if ($tiFilter -ne $null) { #exclude
            for ($i = 0; $i -lt $this.templates.Count; ++$i)  {
                $toRemove = $false;
                if ($tiFilter -contains $this.templates[$i].templateName) {
                    $toRemove = $true;
                }
                
                if ($toRemove) {
                    $this.templates.RemoveAt($i);
                    $i--;
                }
            
            }
        }


        # Скрипты вложенных шаблонов
        for ($i = 0; $i -lt $this.templates.Count; ++$i) {
            [void]$this.us.Add(
                @{ 
                    id = $i;
                    updates = $this.templates[$i].GetUpdateScripts();
                    updateDelta = [timespan]::Zero;
                }
            );
        }
    }

    [void]CheckPing() {
        $this.ping = (Test-Connection -ComputerName ($this.address) -Count 1 -ErrorAction SilentlyContinue).ResponseTime;
    }

    [void]Update()  
    {
        $this.UpdateDeltaTotal = [timespan]::Zero;
        $this.UpdateDeltaTemplates = [timespan]::Zero;

        $this.CheckPing();

        if ($this.ping -eq $null) { return; }    

        $uss = Invoke-Command -ComputerName ($this.address) -SessionOption (New-PSSessionOption -NoCompression -NoMachineProfile -IdleTimeout 300000) -ScriptBlock {
            param([object]$us)
            $ProgressPreference = "SilentlyContinue"
            $UpdateScripts = $us.us;
            $UpdateScriptsCount = $UpdateScripts.Count;           
            $ssw = New-Object 'System.Diagnostics.Stopwatch';
            for ($i = 0; $i -lt $UpdateScriptsCount; ++$i) {
                $UpdateScript = $UpdateScripts[$i];
                $updates = $UpdateScript.updates;
                $scriptsCount = $updates.Count;                
                $ssw.Restart();
                for ($j = 0; $j -lt $scriptsCount; ++$j) {
                    $update = $updates[$j];         
                    # Invoke-Expression makes an irrational shit. Don't use it.	
                    $update.CurrentValue = [scriptblock]::Create('try { ' + $update.Script + ' } catch { $_.Exception.Message + $_.InvocationInfo.PositionMessage  }').InvokeReturnAsIs($null);
                }
                $UpdateScript.UpdateDelta = $ssw.Elapsed;
            }
            $ssw.Stop();            

            return $UpdateScripts;
            
        } -ArgumentList @{us=$this.us};

        if ($uss -eq $null){ return; }
        
        # Process updates of host
        if ($uss -is [array]){
            $this.us = $uss;
            $updateScript = $this.us[0].updates;
            if ($this.us[0].updateDelta -ne $null) {
                $this.UpdateDeltaTotal += $this.UpdateDelta = $this.us[0].updateDelta;
            }
        }
        else {              
            $updateScript = $uss.updates;
            if ($uss.updateDelta -ne $null) {
                $this.UpdateDeltaTotal = $this.UpdateDelta = $uss.updateDelta;
            }
        }
        for ($j = 0; $j -lt $updateScript.Count; ++$j) {
            $this.updateScripts[$j] = $updateScript[$j];
        }

        
        # Process updates of templates
        if ($this.us -is [System.Collections.ArrayList]) {
            for ($i = 1; $i -lt $this.us.Count; ++$i) 
            {
                $updateData = $this.us[$i];
                $this.UpdateDeltaTemplates += $updateData.updateDelta;

                $template = $this.templates[$updateData.id];
                $template.UpdateDelta = $updateData.updateDelta;      
                
                for ([int]$j = 0; $j -lt $updateData.updates.Count; ++$j) {
                    $template.updateScripts[$j] = $updateData.updates[$j];
                }
            }

            $this.UpdateDeltaTotal += $this.UpdateDeltaTemplates;
        }        

        
    }

    [void]Check()
    {
        $this.Checked = [System.Collections.Generic.List[TriggerInfo]]::new();

        $pingTrigger = [TriggerInfo]::new();
        $pingTrigger.Host = $this.hostName;
        $pingTrigger.Template = '';
        $pingTrigger.Item = "ping";
        $pingTrigger.Description = {return "PING FAIL! " + $args[0].hostName.ToString()}.Invoke($this);
        $pingTrigger.Status = ($this.ping -eq $null);
  
        $this.Checked.Add($pingTrigger);

	    if ($this.ping -eq $null) { return; }

        if ($this.triggers.Count -gt 0){
            foreach ($i in 0..($this.triggers.Count-1)) {
                $this.triggers[$i].Check($this);
            }
        }
        $this.Checked.AddRange($this.triggers);

        foreach ($i in 0..($this.templates.Count-1)) {
            $templateResult = $this.templates[$i].GetTriggers();
            $this.Checked.AddRange($templateResult);
        }
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
        return $this.updateScripts.ToArray();
    }

    [TriggerInfo[]]GetTriggers()
    {
        if ($this.triggers.Count -gt 0) {
            foreach ($i in 0..($this.triggers.Count-1)) {
                $this.triggers[$i].Check($this);
            }
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
    $hostNameStr = '';
    if ($info.objectType -eq [ObjectType]::TEMPLATE) {
        $hostNameStr = '$($this.HostRef.HostName)';
    }
    elseif ($info.objectType -eq [ObjectType]::HOST) {
        $hostNameStr = $info.className;
    }
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
`$triggerInfo.Host = "$hostNameStr";
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
    $templateInfo.objectType = [objecttype]::TEMPLATE;

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
	$hostName = '';
	$hostAddress = '';
	$fileName = (Get-Item -Path $path).Name;
	$fileNameParts = $fileName.Split(' ');
	if ($fileNameParts.Length -gt 1) {
		$hostName = $fileNameParts[0];
		$hostAddress = $fileNameParts[1];
	}
	else {
		$hostName=$hostAddress=$fileName;
	}
$useIP = $false;
[ipaddress]$ip = [ipaddress]::None;
if ([ipaddress]::TryParse($hostAddress,[ref]$ip)) {
	$useIP = $true;
}

    $className = $hostName;

    [MetaModel] $hostInfo = [MetaModel]::new();
    $hostInfo.className = $className;
    $hostInfo.objectType = [objecttype]::HOST;

    $body = "
<additionalText>
class <className> : HostBase {
    <defineBody>
`t" + $className + "() : base('$className','$hostAddress') {
        <initBody>
        <templateBody>
        <templateGroupBody>
    }
    
    [void]Update() {
        ([HostBase]`$this).Update();
        <updateBody>
    }
}";
    $additionalText = "";
    $templateBody = "";
    $defineBody = "";
    $initBody = "";
    $updateBody = "";
    $triggerBody = "";    

    $defineRows = [System.Collections.Generic.List[object]]::new();
    $UpdateRows = [System.Collections.Generic.List[object]]::new();

	$initBody += '$this.address = "' + $hostAddress +'";' + [Environment]::NewLine;
	if ($useIP) {
		$initBody += '$this.connectionType = [connectionType]::IP;' + [Environment]::NewLine;
	} else {
		$initBody += '$this.connectionType = [connectionType]::DNS;' + [Environment]::NewLine;
	}
    
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
            if ($lld.Basename[0] -eq '#') { continue; }
            
            $lldInfo = ParseLLDCatalog($path + "\llds\" + $lld.Name);
            #$initBody += $lldInfo.body.Replace("<hostName>",$className);

            $metrics = $null;
            if ($lldInfo.invokation -eq [Invokation]::REMOTE) {                    
                $metrics = Invoke-Command -ComputerName ($className) -scriptblock  $lldInfo.Generator;
            }
            elseif ($lldInfo.invokation -eq [Invokation]::LOCAL) {
                $metrics = $lldInfo.Generator.InvokeReturnAsIs($hostInfo);
            }
            $lldTemplateScript = $lldInfo.GenerateByMetrics($metrics);
            $additionalText += $lldTemplateScript + [System.Environment]::NewLine;
            $templateBody += ("`$this.templates.Add([" + $lldInfo.Classname + "]::new(`$this));`r`n");
        }
    }

    $body = $body.Replace("<className>",$className);
    $body = $body.Replace("<templateBody>",$templateBody); 
    $body = $body.Replace("<defineBody>",$defineBody); 
    $body = $body.Replace("<initBody>",$initBody); 
    $body = $body.Replace("<updateBody>",$updateBody); 
    $body = $body.Replace("<triggerBody>",$triggerBody);
    $body = $body.Replace("<additionalText>",$additionalText);

    $hostInfo.body = $body;

    return $hostInfo;
}

function ParseLLDCatalog ([string] $path) {

    $body = "`$lld = [LLDInfo]::new();`r`n"
    $body += "`$lld.hostRef = `$this`r`n";
    $body += "`$lld.hostName = `"<hostName>`"`r`n";
    $body += "<invokation>`r`n";
    
    <#
    if ((Test-Path -Path $path) -eq $false) {
        return [string[]]::new(0);
    }
    #>

    $fileNameParts = (Get-Item -Path $path).Name.Split(' ');
    $className = $fileNameParts[0];

    $inv = [Invokation]::REMOTE;
    if ($fileNameParts.Length -gt 1) {
        if ($fileNameParts[1].ToLower() -eq 'local') {
            $inv = [Invokation]::LOCAL;
        }
        elseif ($fileNameParts[1].ToLower() -eq 'remote') {
            $inv = [Invokation]::REMOTE;
        }
    }

    $body += "`$lld.className = `"$Classname`"`n";

    $files = Get-ChildItem -Path $path -File;
   
    $defineBody = "";
    $initBody = "";
    $updateBody = "";
    $triggerBody = "";

    $defineRows = [System.Collections.Generic.List[object]]::new();
    $UpdateRows = [System.Collections.Generic.List[object]]::new();

    [LLDInfo] $lldInfo = [LLDInfo]::new();
    $lldInfo.className = $className;
    $lldInfo.invokation = $inv;
    $body = $body.Replace('<invokation>','$lld.invokation = [Invokation]::' + $inv.ToString());

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
                $body += "`$lld.defines.Add($($varDetails[1]),$($varDetails[0]))`r`n";
                $lldInfo.defines.Add($varDetails[1],$varDetails[0]);
            }
        }
        elseif ($block -eq [GeneratorBlock]::GENERATOR) {
            $generatorScript = Get-Content $file.FullName -Raw;
            $lldInfo.generator = [scriptblock]::Create($generatorScript);
            $body += "`$lld.generator = {$generatorScript}`r`n";            
        }
    }
    if ([System.IO.Directory]::Exists($path + "\updates") -eq $true) {        
        $updates = Get-ChildItem -Path ($path + "\updates") -File;
        foreach ($updateFile in $updates) {
            if ($updateFile.BaseName[0] -eq '#') {continue;}

            $updateFileParts = $updateFile.BaseName.Split(" ");
            if ($defineBody -match ($updateFileParts[0] + "[^a-f\d]") -eq $false) { 
                $lldInfo.defines.Add($updateFileParts[0],'object');   
                $body += "`$lld.defines.Add(`"$($updateFileParts[0])`",'object')`r`n";
            }
            
            if ($updateFileParts.Length -ge 2) {
            #...for future
            }

            $scriptText = (Get-Content -Path $updateFile.FullName -Raw);
            $body += "`$lld.updates.Add(`"$($updateFileParts[0])`",{$([System.Environment]::NewLine+$scriptText+[System.Environment]::NewLine)});`n";
            $lldInfo.updates.Add($updateFileParts[0], [scriptblock]::Create($scriptText + [System.Environment]::NewLine));
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
            $lldInfo.triggers.Add( $triggerItemName,@([scriptblock]::Create($triggerScript),$triggerDescription));
            $body += "`$lld.triggers.Add(`"$triggerItemName`",@({$triggerScript},`"$($triggerDescription.Replace('$','`$'))`"));`n";
        }
    }

    $body += "`$this.llds.Add(`$lld);`r`n";        
    

    $lldInfo.className = $className;

    $lldInfo.body = $body;

    return $lldInfo;
}

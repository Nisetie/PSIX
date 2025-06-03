$encoding_main = [Microsoft.PowerShell.Commands.FileSystemCmdletProviderEncoding]::UTF8;


Enum ConnectionType { NONE;IP;DNS }
enum GeneratorBlock { EMPTY;TEMPLATE;DEFINE;INIT;UPDATE;GENERATOR }
enum ObjectType {HOST; TEMPLATE}
enum Invokation {REMOTE; LOCAL}
enum RemoteTool {PS; SH}

class MetaModel {
    [ObjectType]$objectType;
    [string]$className;
    [System.Collections.Generic.Dictionary[string,int]]$variables;
    [System.Collections.Generic.List[string]]$Templates;
    [System.Collections.Generic.List[LLDInfo]]$llds;
    [string]$body;

    MetaModel() {
        $this.variables = [System.Collections.Generic.Dictionary[string,int]]::new();
        $this.Templates = [System.Collections.Generic.List[string]]::new();
        $this.llds = [System.Collections.Generic.List[LLDInfo]]::new();
    }
}

class LLDInfo {
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

    LLDInfo() {
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

        $temp = ""; # filter for final definition of LLD-class

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

class TriggerInfo {
    [string]$Host; [string]$Template; [string]$Item;
    [datetime] $CheckTimestamp;
    [bool]$Status;
    [scriptblock] $Script; [scriptblock] $DescriptionScript;
    [string] $Description; # buffer for $DescriptionScript's result

    TriggerInfo(){
        $this.CheckTimestamp = [datetime]::MinValue;
        $this.Status = $false;
    }

    [void]Check([HostBase]$node) {
        $this.Status = ($this.Script.InvokeReturnAsIs($node) -eq $true);
        $this.Description = $this.DescriptionScript.InvokeReturnAsIs($node);
        $this.CheckTimestamp = [datetime]::Now;
    }
}

class UpdateScript {
	[string]$TemplateName; 
    [string]$ElementName;
	[string]$Script;
    [RemoteTool] $RemoteTool;
    [bool]$IsLocal;
    [object]$CurrentValue;
	[datetime]$UpdateTimestamp;
    [timespan]$UpdateDelta;	    

    UpdateScript() {
        $this.TemplateName = [string]::Empty;
        $this.ElementName = [string]::Empty;
        $this.Script = [string]::Empty;
        $this.RemoteTool = [RemoteTool]::PS;
        $this.IsLocal = $false;
        $this.CurrentValue = $null;
        $this.UpdateTimestamp = [datetime]::MinValue;
        $this.UpdateDelta = [timespan]::Zero;
    }
}

class HostBase
{
    [datetime]$UpdateTimestamp;
	[timespan]$UpdateDelta;
    [timespan]$UpdateDeltaTemplates;
	[timespan]$UpdateDeltaTotal;
    [ConnectionType]$connectionType;
    [string]$FQDN;
    [string]$ip;
    [object]$ping;
    [string]$hostName;
	[string]$address;
    [System.Collections.Generic.Dictionary[int,TemplateBase]]$templates;
    [System.Collections.Generic.Dictionary[int,UpdateScript]]$updateScripts;
    [System.Collections.Generic.List[TriggerInfo]]$triggers;
    [System.Collections.Generic.List[LLDInfo]]$llds;
    [object]$checked;

    HostBase([string]$hostN,[string]$address) {
        $this.hostName = $hostN;
	    $this.address = $address;
        $this.templates = [System.Collections.Generic.Dictionary[int,TemplateBase]]::new();
        $this.updateScripts = [System.Collections.Generic.Dictionary[int,UpdateScript]]::new();
        $this.triggers = [System.Collections.Generic.List[TriggerInfo]]::new();
        $this.llds =  [System.Collections.Generic.List[LLDInfo]]::new();
    }

    [System.Array]GetUpdateScripts()
    {
        return @($this.updateScripts);
    }

    [void]CheckHostName() {
        try {
		    if ($this.connectionType -eq [connectionType]::DNS) {
			    $this.FQDN = [System.Net.Dns]::GetHostByName($this.address).Hostname;
			    $this.ip = [System.Net.Dns]::GetHostByName($this.address).AddressList[0].IPAddressToString;
		    } else {
			    $this.ip = $this.address;		
                $this.FQDN = [System.Net.Dns]::GetHostByAddress($this.address).Hostname;			    
		    }
        } catch { }
    }

    [void]CheckPing() {
        $this.ping = (Test-Connection -ComputerName ($this.address) -Count 1 -ErrorAction SilentlyContinue).ResponseTime;
    }

    [void]Update()  
    {
        $sw = New-Object System.Diagnostics.Stopwatch;

        $this.UpdateTimestamp = [datetime]::Now;
        $this.UpdateDeltaTotal = [timespan]::Zero;
        $this.UpdateDeltaTemplates = [timespan]::Zero;

        $this.CheckPing();
        $this.CheckHostName();

        if ($this.ping -eq $null) {return;}

        # подготовка
         $scriptBlock = {
            param([array]$us)
            $ProgressPreference = "SilentlyContinue";        
            $sw = New-Object 'System.Diagnostics.Stopwatch';
            $us | %{
                    $update = $_.Value;
                    $sw.Reset();
                    $sw.Start();
                    # Invoke-Expression makes an irrational shit. Don't use it.	
                    $update.CurrentValue = [scriptblock]::Create('try { ' + $update.Script + ' } catch { $_.Exception.Message + [System.Environment]::NewLine + $_.InvocationInfo.PositionMessage  }').InvokeReturnAsIs($null);
                    $update.UpdateDelta = $sw.Elapsed;
                    $update.UpdateTimestamp = [datetime]::Now;
                }
            $sw.Stop();
            $sw = $null;
            return @(,$us);            
        };

        $sessionOptions = New-PSSessionOption -NoMachineProfile -IdleTimeout 300000;         
        
        $remoteMetrics = @(,($this.updateScripts.GetEnumerator()|?{$_.Value.IsLocal -eq $false -and $_.Value.RemoteTool -eq [RemoteTool]::PS}|Select-Object *));
        if (!($remoteMetrics.Count -eq 1 -and $null -eq $remoteMetrics[0])) {

            if ($this.connectionType -eq [ConnectionType]::DNS) {
                $session = New-PSSession ($this.address) -SessionOption $sessionOptions;
            } else {
                $session = New-PSSession ($this.address) -Authentication Negotiate -SessionOption $sessionOptions;
            }

            # подготовка удаленных метрик хоста
            $updateScriptsInvoked = Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $remoteMetrics;       
            if ($null -eq $updateScriptsInvoked) { return; }
            if ($updateScriptsInvoked -is [System.Collections.IEnumerable]) {
                $updateScriptsInvoked | % { $this.ProcessUpdated($_.Key, $_.Value); }
            }
            else { $this.ProcessUpdated($updateScriptsInvoked.Key, $updateScriptsInvoked.Value); }

            Remove-PSSession $session;
        }
         
        # обработка локальных метрик хоста
        $this.updateScripts.GetEnumerator()|?{$_.Value.IsLocal -eq $true -and $_.Value.RemoteTool -eq [RemoteTool]::PS}|ForEach-Object{
            $updateScript = $_.Value;
            $sw.Restart();
            try { 
                $updateScript.CurrentValue = [scriptblock]::Create($updateScript.Script).InvokeReturnAsIs($null); 
            } catch { 
                $updateScript.CurrentValue = $_.Exception.Message + [System.Environment]::NewLine + $_.InvocationInfo.PositionMessage  
            }
            $sw.Stop();
            $updateScript.UpdateDelta = $sw.Elapsed;
            $updateScript.UpdateTimestamp = [datetime]::Now;            
            $this.UpdateDelta += $sw.Elapsed;            
        } 
        
        # обработка метрик хоста по ssh
        $u = whoami;
        $a = $this.address;
        $this.updateScripts.GetEnumerator() |`
            Where-Object {$_.Value.RemoteTool -eq [RemoteTool]::SH} |`
            ForEach-Object {
                $updateScript = $_.Value;
                $sw.Restart();
                if ($_.Value.IsLocal -eq $false) {
                    $updateScript.CurrentValue = ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=2 $u@$a -o ServerAliveInterval=1 -o ServerAliveCountMax=2 "$($updateScript.Script)" 2>&1;
                }
                else { $updateScript.CurrentValue = & $updateScript.Script 2>&1; }
                $sw.Stop();
                $updateScript.UpdateDelta = $sw.Elapsed;
                $updateScript.UpdateTimestamp = [datetime]::Now;            
                $this.UpdateDelta += $sw.Elapsed;            
            };       
        
        $this.UpdateDeltaTotal += $this.UpdateDelta;

        # обработка метрик шаблонов
        $this.templates.GetEnumerator() | ForEach-Object {
            $template = $_.Value;

            $remoteMetrics = @(,($template.updateScripts.GetEnumerator()|?{$_.Value.IsLocal -eq $false -and $_.Value.RemoteTool -eq [RemoteTool]::PS}|Select-Object *));
            if (!($remoteMetrics.Count -eq 1 -and $null -eq $remoteMetrics[0])) {

                if ($this.connectionType -eq [ConnectionType]::DNS) {
                    $session = New-PSSession ($this.address) -SessionOption $sessionOptions;
                } else {
                    $session = New-PSSession ($this.address) -Authentication Negotiate -SessionOption $sessionOptions;
                }

                $updateScriptsInvoked = Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $remoteMetrics;       
                if ($null -eq $updateScriptsInvoked) { return; }
                    if ($updateScriptsInvoked -is [System.Collections.IEnumerable]) { 
                        $updateScriptsInvoked | % { $template.ProcessUpdated($_.Key, $_.Value); }
                    }
                    else { $template.ProcessUpdated($updateScriptsInvoked.Key, $updateScriptsInvoked.Value); }     
                    
                Remove-PSSession $session;
            }
                
            $template.updateScripts.GetEnumerator()|`
                Where-Object{$_.Value.IsLocal -eq $true -and $_.Value.RemoteTool -eq [RemoteTool]::PS}|`
                ForEach-Object{
                    $updateScript = $_.Value;
                    $sw.Restart();
                    try { 
                        $updateScript.CurrentValue = [scriptblock]::Create($updateScript.Script).InvokeReturnAsIs($null); 
                    } catch { 
                        $updateScript.CurrentValue = $_.Exception.Message + [System.Environment]::NewLine + $_.InvocationInfo.PositionMessage  
                    }
                    $updateScript.UpdateDelta = $sw.Elapsed;
                    $updateScript.UpdateTimestamp = [datetime]::Now;            
                    $template.UpdateDelta += $sw.Elapsed;            
                }            
            $this.UpdateDeltaTemplates += $template.UpdateDelta;

            # обработка метрик шаблона по ssh
            $u = whoami;
            $template.updateScripts.GetEnumerator() |`
                Where-Object {$_.Value.RemoteTool -eq [RemoteTool]::SH} |`
                ForEach-Object {
                    $updateScript = $_.Value;
                    $sw.Restart();
                    if ($_.Value.IsLocal -eq $false) {
                        $updateScript.CurrentValue = ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=2 $u@$a -o ServerAliveInterval=1 -o ServerAliveCountMax=2 "$($updateScript.Script)" 2>&1;
                    }
                    else { $updateScript.CurrentValue = & $updateScript.Script 2>&1; }
                    $sw.Stop();
                    $updateScript.UpdateDelta = $sw.Elapsed;
                    $updateScript.UpdateTimestamp = [datetime]::Now;            
                    $template.UpdateDelta += $sw.Elapsed;            
                };   
                
                $this.UpdateDeltaTemplates += $template.UpdateDelta;
        }

        $this.UpdateDeltaTotal += $this.UpdateDeltaTemplates;
    }

    [void]ProcessUpdated([int]$id,[object]$updated) {
        $updateScript = $this.updateScripts[$id];
        $updateScript.CurrentValue = $updated.CurrentValue;
        $updateScript.UpdateTimestamp = $updated.UpdateTimestamp;
        $updateScript.UpdateDelta = $updated.UpdateDelta;
        $this.UpdateDelta += $updated.UpdateDelta
    }

    [void]Check()
    {
        $this.Checked = [System.Collections.Generic.List[TriggerInfo]]::new();

        $pingTrigger = [TriggerInfo]::new();
        $pingTrigger.Host = $this.hostName;
        $pingTrigger.Template = '';
        $pingTrigger.Item = "ping";
        $pingTrigger.Description = "PING FAIL! $($this.hostName.ToString())";
        $pingTrigger.Status = ($this.ping -eq $null);
        $pingTrigger.CheckTimestamp = [datetime]::Now;
  
        $this.Checked.Add($pingTrigger);

	    if ($this.ping -eq $null) { return; }

        if ($this.triggers.Count -gt 0){
            foreach ($i in 0..($this.triggers.Count-1)) {
                $this.triggers[$i].Check($this);
            }
        }
        $this.Checked.AddRange($this.triggers);

        if ($this.templates.Count -gt 0) {
            foreach ($i in 0..($this.templates.Count-1)) {
            $templateResult = $this.templates[$i].GetTriggers();
            $this.Checked.AddRange($templateResult);
        }
        }
    }    
}

class TemplateBase
{
	[timespan]$UpdateDelta;
    [string]$templateName;
    [HostBase]$hostRef;
    [System.Collections.Generic.Dictionary[int,UpdateScript]]$updateScripts;
    [System.Collections.Generic.List[TriggerInfo]]$triggers;

    TemplateBase([HostBase]$hostReference)
    {
        $this.hostRef = $hostReference;
        $this.templateName = $this.GetType().Name;
        $this.updateScripts = [System.Collections.Generic.Dictionary[int,UpdateScript]]::new();
        $this.triggers = [System.Collections.Generic.List[TriggerInfo]]::new();
        $this.UpdateDelta = [timespan]::Zero;
    }

    [void]ProcessUpdated([int]$id,[object]$updated) {
        $updateScript = $this.updateScripts[$id];
        $updateScript.CurrentValue = $updated.CurrentValue;
        $updateScript.UpdateTimestamp = $updated.UpdateTimestamp;
        $updateScript.UpdateDelta = $updated.UpdateDelta;
        $this.UpdateDelta += $updated.UpdateDelta
    }

    [System.Collections.Generic.Dictionary[int,UpdateScript]]GetUpdateScripts()
    {
        return $this.updateScripts;
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

function GetContent([string]$fileName) {
    return Get-Content -Path $fileName -Encoding $encoding_main -Raw;
}
function SetContent([string]$fileName, [string]$text) {
    Set-Content -Path $fileName -Value $text -Encoding $encoding_main;
}

function ParseUpdatesCatalog([MetaModel]$info,[string]$className,[string]$path) {
    $updates = Get-ChildItem -Path $path -File | Where-Object { $_.Name -like "*.ps1" -or $_.Name -like "*.sh"  };
    $id = 0;
    $initBody = '';
    for ($i = 0; $i -ne $updates.Count; ++$i) {
        $updateFile = $updates[$i];
        if ($updateFile.BaseName[0] -eq '#') {continue;}

        $updateFileFormat = $updateFile.Extension.ToLower();
        if ($updateFileFormat -eq ".ps1") {$updateFileFormat = [RemoteTool]::PS;}
        elseif ($updateFileFormat -eq ".sh") {$updateFileFormat = [RemoteTool]::SH;}

	    $updateFileParts = $updateFile.BaseName.Split(" ");
		
        $isLocal = $false;
        if ($updateFile.Basename -match '\slocal\s*') { $isLocal = $true; }
	
        $scriptText = GetContent $updateFile.FullName;
        $initBody += @"
`$updateScript = [UpdateScript]::new();
`$updateScript.TemplateName = `"$className`";
`$updateScript.ElementName = `"$($updateFileParts[0])`";
`$updateScript.CurrentValue = `$null;
`$updateScript.Script = '$($scriptText.Replace("'","''"))';
`$updateScript.UpdateTimestamp = [datetime]::MinValue;
`$updateScript.IsLocal = `$$isLocal;
`$updateScript.RemoteTool = [RemoteTool]::$updateFileFormat;
`$this.updateScripts.Add($id,`$updateScript);

"@;
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
        #$hostNameStr = $info.className;
        $hostNameStr = '$($this.HostName)';
    }
    for ($i = 0; $i -ne $triggers.Count; ++$i) {
        if ($triggers[$i].BaseName[0] -eq '#') {continue;}

        $triggerCatalog = $triggers[$i];
        
        $triggerItemName = $triggerCatalog.BaseName.trim(); 

        if ($triggerItemName[0] -eq '#') { continue; }

        if ((Test-Path -Path ($triggerCatalog.Fullname + "\check.ps1")) -eq $false) { continue; } 

        $triggerScript = GetContent ($triggerCatalog.Fullname + "\check.ps1");

        $triggerDescription = $triggerItemName + "!";
        if ((Test-Path -Path ($triggerCatalog.Fullname + "\message.ps1")) -eq $true) {
            $triggerDescription = GetContent ($triggerCatalog.Fullname + "\message.ps1");
        }

        $s = ($triggerScript | Select-String -AllMatches -pattern '\$this.\w*').Matches | select value;
        foreach ($el in $s) { 
            $el = $el.Value; 
            $triggerScript = ($triggerScript.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $info.variables[$el.Replace("`$this.","")] + "].CurrentValue"));
        }   

        $s = ($triggerDescription | Select-String -AllMatches -pattern '\$this.\w*').Matches | select value;
        foreach ($el in $s) {
            $el = $el.Value; 
            $triggerDescription = ($triggerDescription.Replace($el,$el.Replace($el,"`$args[0].updateScripts[") + $info.variables[$el.Replace("`$this.","")] + "].CurrentValue"));
        }  
        
        $triggerDescription = $triggerDescription.Replace('"','`"');    

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
    $className = $className -replace "[!@#`$%^&-]","_";

    [MetaModel] $hostInfo = [MetaModel]::new();
    $hostInfo.className = $className;
    $hostInfo.objectType = [objecttype]::HOST;

    $body = "
<additionalText>
class <className> : HostBase {
    <defineBody>
`t" + $className + "() : base('$hostName','$hostAddress') {
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
    
    if ([System.IO.File]::Exists($path + "\templates") -eq $true) {            
        $rows = GetContent ($path + "\templates");
        foreach($row in $rows) {
            if ($row -eq "" -or $row[0] -eq "#") { continue; }
            $templateBody += ("`$this.templates.Add(`$this.templates.Count,[" + $row.Trim() + "]::new(`$this));`r`n");
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

            $rows = GetContent $file.FullName;

            foreach($row in $rows) {
                if ($row -eq "" -or $row[0] -eq "#") { continue; }            
                $varDetails = $row.Split(" ");                
                $body += "`$lld.defines.Add($($varDetails[1]),$($varDetails[0]))`r`n";
                $lldInfo.defines.Add($varDetails[1],$varDetails[0]);
            }
        }
        elseif ($block -eq [GeneratorBlock]::GENERATOR) {
            $generatorScript = GetContent $file.FullName;
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

            $scriptText = GetContent $updateFile.FullName;
            $body += "`$lld.updates.Add(`"$($updateFileParts[0])`",{$([System.Environment]::NewLine+$scriptText+[System.Environment]::NewLine)});`n";
            $lldInfo.updates.Add($updateFileParts[0], [scriptblock]::Create($scriptText + [System.Environment]::NewLine));
        }
    }    
    if ([System.IO.Directory]::Exists($path + "\triggers") -eq $true) {        
        $triggers = Get-ChildItem -Path ($path + "\triggers") -Directory;
        foreach ($triggerCatalog in $triggers) {
            $triggerItemName = $triggerCatalog.BaseName; 
            if ($triggerItemName[0] -eq '#') { continue; }
            if ((Test-Path -Path ($triggerCatalog.Fullname + "\check.ps1")) -eq $false) { continue; } 
            $triggerScript = GetContent ($triggerCatalog.Fullname + "\check.ps1");
            $triggerDescription = $triggerItemName + "!";
            if ((Test-Path -Path ($triggerCatalog.Fullname + "\message.ps1")) -eq $true) {
                $triggerDescription = GetContent ($triggerCatalog.Fullname + "\message.ps1");
            }
            $lldInfo.triggers.Add( $triggerItemName,@([scriptblock]::Create($triggerScript),$triggerDescription));
            $body += "`$lld.triggers.Add(`"$triggerItemName`",@({$triggerScript},`"$($triggerDescription.Replace('$','`$'))`"));`n";
        }
    }

    $body += "`$this.llds.Add(`$lld);`r`n";        
    

    $lldInfo.className = $className;

    $lldInfo.body = $body;

    return $lldInfo;
}

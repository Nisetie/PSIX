PSIX (Powershell: Systems Integrity eXplorer)

Repository: https://github.com/Nisetie/PSIX

Development started: Nov 2019

Inspired By Zabbix and Mamashev-Man.

This tool implements task of retreiving an information about defined metrics and criterias. Then using them to check system(-s) states and stability.
User can make hosts, templates, template groups and LLDs like in Zabbix.

PSIX is not a full alternative of Zabbix. But can be useful, when you want to collect metrics with difficult evaluations.

PSIX support additional plugins. Which can process an information of host's metrics after his update and do something else with it. For examplse, send metrics to Zabbix.

System requirements and setting For "server" machine:
- Windows Management Framework 5.1 with PowerShell 5.1 (https://www.microsoft.com/en-us/download/details.aspx?id=54616) or later.
  - For Windows 2012 R2: KB3191564
- Disable firewall or add rules for passing traffic from/to all checking hosts.
- For stop prompting script's executions (powershell command): Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force
- If there is no domain network and DNS, add ip addresses or hostnames of machines to TustedHosts list:
  - Set-Item WSMan:\localhost\Client\TrustedHosts -Value { <ComputerName>,[<ComputerName>] | * } -Force
 
Notes:

1. In current version works stable with hosts in domain. Doesn't tested with hosts without AD and DNS.
2. ...

Short example:

1.Fill Hosts directory.

Example:
Hosts \Host1\
- templates.txt
- Updates\
- Triggers\

Where "Host1" is a hostname of ip-address.

Add to tempates.txt: "MyTemplate"
Add to Updates\ textfile "Datetime.txt". Write ti this file: (Get-Date).ToString("u")

This metric will store only current time of host. But you can write any script than returns serialized data: numbers, strings.

Add to Triggers\ folder "DateTimeCheck".
- Add to this folder textfile "check.txt". Write to this file: [datetime]::Parse($this.DateTime).Year -eq (Get-Date).Year
- Add to this folder textfile "message.txt". Write to this file: "Today is $($this.Datetime)!"

This trigger just checks Datetime-metric. After Checking this host will store information with this executed trigger.
Trigger can have any name. You can set a name of realted metric for a trigger.
You can write almost any powershell script in check.txt. But can use only metrics of this host or current template.

2.Fill Templates directory.

Example:
Templates \MyTemplate\
- Updates\
- Triggers\

Templates are used by hosts when you don't want to dublicate metrics and triggers for each host's folder.

Filling rules of templates are the same as for hosts.

3.Fill HostGroups.

Example:
HostGroups \<GroupName>\
- templates.txt
- hosts.txt

HostGroups are used for cases when you want to apply set of templates to set of hosts.

In templates.txt you must write templates on each row.
In templates.txt you must write hosts on each row.

4.After configuring you must run th script: Build.ps1. This script analyzes configuration and creates running script in these folders:
- RuntimeHosts
- RuntimeTemplates

5.Disable on enable plugins in Plugins/ folder. Just add or remove from a beginning of each file "#" character.

For default I recommend: AlarmsLogger, MetricsLogger, TriggersLogger.

6.To execute scanning you must run this script under admin rights: Run.ps1 or Run.bat.

7.After scan finish all result data will by stored in Live/ folder.

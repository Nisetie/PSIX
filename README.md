PSIX (Powershell: Systems Integrity eXplorer)

Repository: https://github.com/Nisetie/PSIX

Development started: Nov 2019

Inspired By Zabbix and Mamashev-Man.

This tool implements task of retreiving information about defined metrics and criterias. Then using them to check system(-s) states and stability.
User can make hosts, templates, template groups and LLDs like in Zabbix.

PSIX is not a full alternative of Zabbix. But can be useful, when you want to collect metrics with difficult evaluations.

PSIX support additional plugins. Which can process an information of host's metrics after his update and do something else with it. For examplse, send metrics to Zabbix.

System requirements and setting For "server" machine:
- Windows Management Framework 5.1 with PowerShell 5.1 (https://www.microsoft.com/en-us/download/details.aspx?id=54616) or later.
  - For Windows 2012 R2: KB3191564
- Disable firewall or add rules for passing traffic from/to all checking hosts.
- For stop promting of scripts executions (powershell command): Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force
- Add ip addresses of machines to TustedHosts list:
  - Set-Item WSMan:\localhost\Client\TrustedHosts -Value <ComputerName>,[<ComputerName>]

Notes:
1. In current version works stable with hosts in domain. Doesn't tested with hosts without AD and DNS.
2. ...

Short instruction:
1.Fill Hosts directory.

Example:
Hosts \<HostName>\
- [templates.txt]
- Updates\
- Triggers\
- LLDs\

2.Fill Templates directory.

Example:
Templates \<TemplateName>\
- Updates\
- Triggers\
- LLDs\

3.Fill HostGroups.

Example:
HostGroups \<GroupName>\
- templates.txt
- hosts.txt


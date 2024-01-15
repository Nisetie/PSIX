# PSIX (Powershell: Systems Integrity eXplorer)

Repository: https://github.com/Nisetie/PSIX

Начало разработки: ноябрь 2019 года.

Взятые за основу идеи и вдохновители: Zabbix, Человек-Мамашев, желание сделать простейший и универсальный сборщик метрик на базе коробочной комплектации ОС Windows.

## Коротко о системе

Данный инструмент выполняет задачу сбора информации по заданным метрикам с различных систем (компьютеров, служб и ПО). Собранная информация в соответствии с заданными критериями оценивается для определения состояния работы систем и их компонентов.
Пользователь может составить список хостов, их группы, шаблоны метрик и низкоуровневого обнаружения (как LLD в Zabbix).

PSIX не являются полноценной заменой других известных систем сбора метрик и мониторинга. Рекомендуемые способы использования:
- промежуточное звено между Zabbix и хостами для метрик с действительно сложной логикой, требующей выполнения множества действий;
- небольшая система сбора метрик.

Недостатки PSIX это недостатки самого Powershell:
- низкая производительность скриптов (по сравнению с компилируемыми языками программирования);
- временные издержки при установке связи между "сервером" и хостами и при передаче информации по сети в виде сериализованных объектов.

Основые части PSIX:
- модуль ядра, содержащий команды построения модели сбора данных и взаимодействия сервера и хостов
- плагины, которые решают обособленные задачи по обработке собранных метрик.

PSIX поддерживает пользовательские плагины. Как пример, можно создать и добавить плагин генерации веб-страницы со сводной информацией по метрикам и триггерам.
Основные уже включенные в репозиторий плагины:
- TriggersLogger - выгрузка всех триггеров
- AlarmsLogger - выгрузка сработавших триггеров
- MetricsLogger - выгрузка всех метрик и их значений
- ZabbixLogger - отправка на сервер Zabbix данных о сработавших триггерах и метаданных для LLD (для генерации триггеров) 

Системные требования:
- Операционная система со встроенным PowerShell или с поддержкой его установки.
- PowerShell версии 5.1 и больше. Так для Windows 2012 R2 необходимо установить пакет обновления KB3191564.
- Выключение службы Firewall или включение правил на пропуск трафика между определенными хостами.
- Выключить постоянный запрос подтвержения на запуск скриптов PowerShell: Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force
- Если хосты не в домене, тогда надо добавить адреса или имена хостов с список доверенных: Set-Item WSMan:\localhost\Client\TrustedHosts -Value { <ComputerName>,[<ComputerName>] | * } -Force
- Более подробная информация о том, как наладить работу удаленных команд PowerShell: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_remote_troubleshooting?view=powershell-5.1
 
## Примеры использования. 

Сделаем сбор текущего времени на хосте и сравнения его с временем на сервере.

1. Заполнить каталог Hosts каталогами с именами контролируемых хостов.

Примерная структура каталогов:

Hosts \Host1\
- templates.txt
- Updates\
- Triggers\

Где "Host1" это имя в сети или ip-адрес.

Добавьте в каталог Updates\ файл "Datetime.txt". Введите в файле строку: (Get-Date).ToString("u")

Это будет простой сбор времени в формате UTC. Но в целом можно таким образом получать и возвращать любую информацию, которую можно представить в виде числа или строки.


Добавьте в каталог Triggers\ папку "DateTimeCheck".

Добавить в папку файл "check.txt". Этот файл должен содержать скрипт проверки. Введите в файле строку: [datetime]::Parse($this.DateTime).Year -eq (Get-Date).Year

Обратите внимание, что для обращения к ранее созданной метрике используется следующий синтаксис: $this.<имяМетрики>. Так как дата передается на сервер в виде строки, то при проверке надо её преобразовать обратно в дату. Под "$this" подразумевается объект хоста, в контексте которого анализируется информация.

Это будет проверка времени на стороне сервера. Если год на хосте совпадает с годом на сервере (проверка вернет $True), тогда триггер сработает. Логично было бы вернуть $False, а True получать при неравенстве года, но в примере необходимо показать работу всех механизмов. Поэтому специально сделано ложное срабатываение триггера. Продолжим...

Добавить в папку файл "message.txt". Этот файл должен содержать осмысленное сообщение триггера. Введите в файле строку: "Today is $($this.Datetime)!"

В сообщении триггера можно подставлять текущие значения метрик для большей информативности. Для этого используется синтаксис: $($this.<имяМетрики>).

2. Заполнить каталог шаблонов.

Example:
Templates \MyTemplate\
- Updates\
- Triggers\

Templates are used by hosts when you don't want to dublicate metrics and triggers for each host's folder.

Filling rules of templates are the same as for hosts.

3. Заполнить каталог групп хостов.

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

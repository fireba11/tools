# Microsoft ActiveDirectory Monitoring - Replication Check (with performance counters from DRA)
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Revision History:
# 2012-08-25	Bastian W. [Bastian@gmx-ist-cool.de]		1.0 (initial version)
# 2016-03-20	Bastian W. [Bastian@gmx-ist-cool.de]		1.1  code adjusted:
#																* updated script for Windows 2012R2 compatibility
#
# Info:
# This powershell plugin for the NSClient++ can be used to monitor the replication (and performance counters) from a Microsoft ActiveDirectory Domain Controller based on Windows 2008 / 2008 R2
# It monitors the domain controllers replication status with its neighbors and if the number of consecutive sync failures will be '0' (means there is no error during replication) it collects performance counters from the DRA (directory replication agent). If the sync error value is greater than '1' for any partition for any neighbor, an error will be flagged and the failed neighbor will be reported to nagios and an additional email is send out to a system administrator with more infos.
#
# FAQ:
#	How To solve "cannot be loaded because the execution of scripts is disabled on this system. Please see "get-help about_signing" for more details."
# 	See: http://technet.microsoft.com/en-us/library/ee176949.aspx [a possible solution would be 'Set-ExecutionPolicy RemoteSigned']
#
# Installation:
#
# 1.)
# Create a folder on C:\ called "NagiosMonitoring" if it didn´t exist, and put this script into that folder.
#
# Note: If you use another Foldername, you need to change this script completly!
#
# 2.)
# Now start a Powershell and run the following comands (to test if the script is working for you)
# "C:"
# "cd NagiosMonitoring"
# ".\NagiosMonitoring_AD_ReplicationCheck.ps1"
#
# 3.)
# Add this script to the NSClient++ configuration (file: NSC.ini)
#
# [External Scripts]
# ADDCReplicationCheck=cmd /c echo C:\NagiosMonitoring\NagiosMonitoring_AD_ReplicationCheck.ps1 | PowerShell.exe -Command -
#
# 4.)
# On the check_nrpe command include the -t 30, since it takes some time to load the Exchange cmdlet's.
# 
# 5.)
# uncommend CheckExternalScripts.dll in the NSClient++ configuration (file: NSC.ini)
#
# 6.)
# restart the NSClient++ Service
#
# 7.)
# You need to edit the config below
#
#   Configuration:
#   ====================
#   Specify here from which email adress the emails should come from
#   Syntax: $strMailFrom = "ADMonitoringSolution@yourcompany.com";
	$strMailFrom="ADMonitoringSolution@yourcompany.com";
#
#   Specify here to which email adress the notifications should be send to
#   Syntax: $strMailTo = "you@yourcompany.com";
	$strMailTo = "you@yourcompany.com";
#
#   Specify here via which SMTP server the notification emails should be send
#   Syntax: $strMailServer = "yourmailserver.ads";
	$strMailServer = "yourmailserver";
#
#   Specify here which email subject should be used
#   Syntax: $strMailSubject = "MS AD Monitoring - Replication issues detected!";
	$strMailSubject = "MS AD Monitoring - Replication issues detected!";






# =========================================================================================================================
#
# ------------- Do not change anything behind that line ! ----------------------------
#
#
# Buildinfo (ressources user)
# 
# http://msmvps.com/blogs/richardsiddaway/archive/2012/02/05/testing-replication.aspx
# http://technet.microsoft.com/en-us/library/ff730960.aspx
# http://etutorials.org/Server+Administration/Active+directory/Part+III+Scripting+Active+Directory+with+ADSI+ADO+and+WMI/Chapter+26.+Scripting+with+WMI/26.9+Monitoring+Replication/
# 
# Performance Infos:
#  http://www.activexperts.com/activmonitor/windowsmanagement/scripts/activedirectory/monitoring/#MDCP.htm 
#
# Active Directory Replication Traffic:
#   http://technet.microsoft.com/en-us/library/bb742457.aspx
#
# PerformanceCounter for Replication
# http://www.windowsitpro.com/article/performance/jsi-tip-5454-how-do-i-monitor-performance-in-active-directory-
#
# Get replication details
# Get-WmiObject -Namespace root\MicrosoftActiveDirectory -Class MSAD_ReplNeighbor -ComputerName $env:COMPUTERNAME
#
# Get pending objects
# Get-WmiObject -Namespace root\MicrosoftActiveDirectory -Class MSAD_ReplPendingOp -ComputerName $env:COMPUTERNAME

# initialize vars/reset vars to zero
$intSyncErrorCounter=0
$intNagiosStatus = "0"
$strNagiosOutput = ""
$listRepTestResults = ""
$RepTestResultRow = ""
$strNagiosPerfData = ""
$strMailToAdminBody = ""
$intSyncServerErrorCounter=0

function getReplicationInfos
{            
[CmdletBinding()]
param(
 [string]$computername=$env:COMPUTERNAME
)

# LastSyncResult -> Number representing the result of the last sync operation with this neighbor. A value of 0 indicates success.
# NumConsecutiveSyncFailures -> Number of consecutive sync failures between the two neighbors.
# TimeOfLastSyncAttempt -> Time of the last sync attempt.
# TimeOfLastSyncSuccess -> Time of last successful sync attempt.

# Get-WmiObject -Namespace root\MicrosoftActiveDirectory -Class MSAD_ReplNeighbor -ComputerName $env:COMPUTERNAME | select SourceDsaCN, NamingContextDN, LastSyncResult, NumConsecutiveSyncFailures, LastSyncAttempt, LastSyncSuccess

Get-WmiObject -Namespace root\MicrosoftActiveDirectory -Class MSAD_ReplNeighbor -ComputerName $computername|            
select SourceDsaCN, NamingContextDN, LastSyncResult, NumConsecutiveSyncFailures
@{N="LastSyncAttempt"; E={$_.ConvertToDateTime($_.TimeOfLastSyncAttempt)}},
@{N="LastSyncSuccess"; E={$_.ConvertToDateTime($_.TimeOfLastSyncSuccess)}}
}

# get our test result now.
$listRepTestResults = getReplicationInfos 

foreach ($RepTestResultRow in $listRepTestResults)
{
			if ($RepTestResultRow.LastSyncResult -gt 0)
            {
				# we have a failed sync
								
				if ($strNagiosOutput -eq "")
				{
					# this is our first failed server in our nagios output
					
					# we will count here our failed servers
					$intSyncServerErrorCounter++
					
					$strNagiosOutput = $RepTestResultRow.SourceDsaCN
					
				}
				else
				{
				
					if (-not $strNagiosOutput -like '*'+$RepTestResultRow.SourceDsaCN+'*')
					{
						$strNagiosOutput = ", "+ $RepTestResultRow.SourceDsaCN
						$intSyncServerErrorCounter++
					}
				
				}
							
				$intSyncErrorCounter++
				
				# We could enhance the script to send out a email to the administrators here with more infos and include the result:
				# Get-WmiObject -Namespace root\MicrosoftActiveDirectory -Class MSAD_ReplPendingOp -ComputerName $env:COMPUTERNAME
				# Properties: TimeEnqueued, NamingContextDn, DsaDN, DsaAddress
								
				if ($intSyncErrorCounter -eq 1)
				{
					# we didn´t have a Nagios output here, so we will set one
				
					$strMailToAdminBody = "Replication of "+$RepTestResultRow.NamingContextDN+" from "+$env:COMPUTERNAME+" to "+$RepTestResultRow.SourceDsaCN+" failed with error "+$RepTestResultRow.LastSyncResult
					$strMailToAdminBody = $strMailToAdminBody + "`r`n---------------------------------------------------------------------"
				}
				else
				{
					# we already have a error output, so we will add the new one here
					$strMailToAdminBody = $strMailToAdminBody + "`r`nReplication of "+$RepTestResultRow.NamingContextDN+" from "+$env:COMPUTERNAME+" to "+$RepTestResultRow.SourceDsaCN+" failed with error "+$RepTestResultRow.LastSyncResult
					$strMailToAdminBody = $strMailToAdminBody + "`r`n---------------------------------------------------------------------"
				}
								
				if ($intSyncServerErrorCounter -eq 1)
				{
					# we found one server who has an sync error, so we set the state to warning
					$intNagiosStatus = "1"
				}
				elseif ($intSyncServerErrorCounter -gt 2) 
				{
					# we found two (or more) server who have an sync error, so we set the state to critical
					$intNagiosStatus = "2"
				}			
			}
}

if ($intSyncErrorCounter -eq 0)
{
# we didn´t have an error here, so we will collect now some performance counters.

	# The counter infos came from here:
	# http://technet.microsoft.com/en-us/library/cc961942.aspx

	# And the idea for the cooked values from here:
	# http://blogs.technet.com/b/heyscriptingguy/archive/2010/02/16/hey-scripting-guy-february-16-2010a.aspx

	# DRA Inbound Bytes Total/Sec: This counter shows total bytes received through replication per second. Lack of activity indicates that the network is slowing down replication.
	$strDRAInboundBytesTotal = (Get-counter -ComputerName $env:computername -Counter "\DirectoryServices(NTDS)\DRA Inbound Bytes Total/sec").countersamples[0].CookedValue

	# DRA Inbound Object Updates Remaining in Packet: This counter shows the number of object updates received for replication that have not yet been applied to the local server. The value should be low, with a higher value indicating that the hardware is incapable of adequately servicing replication (warranting a server upgrade).
	$strDRAInboundObjectUpdatesRemaininginPacket = (Get-counter -ComputerName $env:computername -Counter "\DirectoryServices(NTDS)\DRA Inbound Object Updates Remaining in Packet").countersamples[0].CookedValue

	# DRA Outbound Bytes Total/Sec: This counter shows the total bytes sent per second. Lack of activity indicates that the hardware or network is slowing down replication.
	$strDRAOutboundBytesTotal = (Get-counter -ComputerName $env:computername -Counter "\DirectoryServices(NTDS)\DRA Outbound Bytes Total/sec").countersamples[0].CookedValue

	# DRA Pending Replication Synchronizations: This counter indicates the replication backlog on the server. This value should be low, with a higher value indicating that the hardware is not adequately servicing replication.
	$strDRAPendingReplicationSynchronizations = (Get-counter -ComputerName $env:computername -Counter "\DirectoryServices(NTDS)\DRA Pending Replication Synchronizations").countersamples[0].CookedValue

	# Additional values (maybe for further release of the script):
	#DRA Inbound Bytes Not Compressed. Number of bytes replicated in, that were not compressed at the source (which typically implies they arrived from other DSAs in the same site).
	#DRA Inbound Bytes Compressed (Before Compression). Original size in bytes of inbound compressed replication data (size before compression).
	#DRA Inbound Bytes Compressed (After Compression). Compressed size in bytes of inbound compressed replication data (size after compression).
	#DRA Outbound Bytes Not Compressed. Number of bytes replicated out that were not compressed (which typically implies they were sent to DSAs in the same site, or that less than 50,000 bytes of replicated data was sent).
	#DRA Outbound Bytes Compressed (Before Compression). Original size in bytes of outbound compressed replication data (size before compression).
	#DRA Outbound Bytes Compressed (After Compression). Compressed size in bytes of outbound compressed replication data (size after compression).

	$strNagiosPerfData = "|" +" DRAInboundBytesTotal="+$strDRAInboundBytesTotal +" DRAInboundObjectUpdatesRemaininginPacket="+$strDRAInboundObjectUpdatesRemaininginPacket+" DRAOutboundBytesTotal="+$strDRAOutboundBytesTotal+" DRAPendingReplicationSynchronizations="+$strDRAPendingReplicationSynchronizations
}
else
{
# we have some errors and need to inform the administrator via mail

	Send-MailMessage -From $strMailFrom -To $strMailTo -Subject $strMailSubject –Body $strMailToAdminBody –SmtpServer $strMailServer
}


# Output, when should we push out a notification to nagios?
if ($intNagiosStatus -eq "2") 
{
	Write-Host "CRITICAL: Replication with" $strNagiosOutput "failed!"
} 
elseif ($intNagiosStatus -eq "1") 
{
	Write-Host "WARNING: Replication with" $strNagiosOutput "failed!"
} 
else 
{
	Write-Host "OK: replication is up and running" $strNagiosPerfData
}

exit $intNagiosStatus

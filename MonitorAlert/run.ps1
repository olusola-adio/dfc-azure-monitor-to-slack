<#
.SYNOPSIS
Posts an Azure Monitor alert from an action group webhook to Slack

.DESCRIPTION
This azure function takes a HTTP post request,  and posts a message into Slack. 

It requires:

* A POST request be made to /api/MonitorAlert.

* The request must have a "channel" parameter on the query string, and will return a Bad Request status code if it does not.  
This value is the channel (minus the #) that the message will be posted to.

* The environment must have a "SlackToken" variable, containing the slack token to use to post to slack with.  
The request will return a HTTP bad status if it does not exist.

*  The request body must contain the json for the alert.  

A schema for the payload can be found at the following link:

https://docs.microsoft.com/en-us/azure/azure-monitor/platform/alerts-metric-near-real-time#payload-schema

Some possible improvements:
    * Update to add support for the common alert schema

.PARAMETER Request

The request object. This is populated via the Azure Function runtime.

.PARAMETER TriggerMetadata

Meta-data about the functions invocation. Populated by the Azure Function runtime.

#>

using namespace System.Net

param($Request, $TriggerMetadata)

Import-Module MonitorAlertHelperModule

Write-Host "PowerShell HTTP trigger function processed a request."

$channel = $Request.Query.Channel
$slackToken = $env:SLACKTOKEN

if ([string]::IsNullOrWhiteSpace($channel)) {
    Push-OutputBindingWrapper -Status BadRequest -Body "channel not specified in query"   
    return
}

if ([string]::IsNullOrWhiteSpace($slackToken)) {
    Push-OutputBindingWrapper -Status BadRequest -Body "Slack token not specified"   
    return
}

if($null -eq $request.Body) { 
    Push-OutputBindingWrapper -Status BadRequest -Body "Unable to parse body as json"
    return
}

$message = New-SlackMessageFromAlert -alert $Request.Body.data -channel $channel

try {    
    Send-MessageToSlack -slackToken $slackToken -message $message            
}
catch {
    Push-OutputBindingWrapper -Status BadRequest -Body ("Unable to send slack message:", $_.Exception.Message)
    return     
}

Push-OutputBindingWrapper -Status OK -Body "Message successfully sent to slack!"
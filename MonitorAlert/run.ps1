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

Write-Host "PowerShell HTTP trigger function processed a request."


function EncodeSlackHtmlEntities {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ToEncode
    )
<#
.SYNOPSIS

Encodes HTML entities

.DESCRIPTION

Encodes the HTML entities according to slack guidelines (https://api.slack.com/docs/message-formatting)

.Parameter ToEncode

The string to encode

.OUTPUTS

System.String. The encoded string

#>    
    
    $encoded = $ToEncode.Replace("&", "&amp;"). `
        Replace("<", "&lt;"). `
        Replace(">", "&gt;")

    return $encoded
}

function New-SlackMessageFromAlert
{
<#
.SYNOPSIS

Creates a slack message object from alert data

.DESCRIPTION

Creates an object representing a slack message from given azure monitor alert message data.

.Parameter channel

The slack channel to pipe the alert into

.Parameter alert

An object representing the alert 

.OUTPUTS

hashtable. The slack message
#>

    param(
        [Parameter(Mandatory=$true)]
        [string] $channel,
        [Parameter(Mandatory=$true)]
        [object] $alert
    )

    $alertAttachmentColours = @{
        "Activated" = "#ff0000"
        "Deactivated" = "#00a86b"
    }

    $lowerAlertStatus = $alert.status.ToLower()
    
    $encodedResourceName = EncodeSlackHtmlEntities -ToEncode $alert.context.resourceName
    $encodedRuleName = EncodeSlackHtmlEntities -ToEncode $alert.context.name

    $encodedMetricName = EncodeSlackHtmlEntities -ToEncode $alert.context.condition.allOf[0].metricName
    $encodedMetricOperator = EncodeSlackHtmlEntities -ToEncode $alert.context.condition.allOf[0].operator
    $encodedMetricThreshhold = EncodeSlackHtmlEntities -ToEncode $alert.context.condition.allOf[0].threshold
    $portalLink = $alert.context.portalLink
    
    $slackMessage = @{ 
        channel = "#$($channel)"
        attachments = @(
            @{
                color = $alertAttachmentColours[$alert.status]
                "title_link" = $portalLink
                title = "Alert $($lowerAlertStatus) for $($encodedResourceName)"
                text = "The following metric rule belonging to $($encodedRuleName) has been $($lowerAlertStatus):`n`n$($encodedMetricName) $($encodedMetricOperator) $($encodedMetricThreshhold)`n`nPlease visit the resource <$($portalLink)|in the portal> for more information."
            }
        ) 
    }

    return $slackMessage
}

function Push-OutputBindingWrapper 
{
    param(
        [Parameter(Mandatory=$true)]
        [HttpStatusCode] $Status,
        [string] $Body=""
    )
<#
.SYNOPSIS

A wrapper for pushing an HTTP Status and Body text to the azure functions output binding

.DESCRIPTION

A wrapper for pushing an HTTP Status and Body text to the azure functions output binding

.Parameter Status

HttpStatusCode. A member of the HttpStatusCode enumberation to send as the result of the current operation 

.Parameter Body

String.  The text to return to the client.

#>


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ 
        StatusCode = $Status
        Body = $Body
    })
}

function Send-MessageToSlack 
{
    param(
        [Parameter(Mandatory = $true)]
        [string] $slackToken,
        [Parameter(Mandatory=$true)]
        [hashtable] $message
    )
<#
.SYNOPSIS

Sends a message to Slack

.DESCRIPTION

Sends an hashtable to slack using the given token.

.Parameter slackToken

String. The slack token to use to communicate with slack.

.Parameter $message

hashtable.  A hashtable representing the message to send to slack.
#>

    $serializedMessage = "payload=$($message | ConvertTo-Json)"

    Invoke-RestMethod -Uri https://hooks.slack.com/services/$($slackToken) -Method POST -UseBasicParsing -Body $serializedMessage
}

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
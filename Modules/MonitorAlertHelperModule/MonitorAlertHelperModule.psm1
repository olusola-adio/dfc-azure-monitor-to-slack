<#
.SYNOPSIS
Helper functions for the MonitorAlert Azure Function

.DESCRIPTION
A module full of helper functions for the MonitorAlert Azure Function

#>


function EncodeSlackHtmlEntities {
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
    param(
        [Parameter(Mandatory = $true)]
        [string] $ToEncode
    )
  
    
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
        [string] $Channel,
        [Parameter(Mandatory=$true)]
        [hashtable] $Alert
    )

    $alertAttachmentColours = @{
        "Activated" = "#ff0000"
        "Deactivated" = "#00a86b"
    }

    $lowerAlertStatus = $Alert.status.ToLower()
    
    $encodedResourceName = EncodeSlackHtmlEntities -ToEncode $Alert.context.resourceName
    $encodedRuleName = EncodeSlackHtmlEntities -ToEncode $Alert.context.name

    $encodedMetricName = EncodeSlackHtmlEntities -ToEncode $Alert.context.condition.allOf[0].metricName
    $encodedMetricOperator = EncodeSlackHtmlEntities -ToEncode $Alert.context.condition.allOf[0].operator
    $encodedMetricThreshhold = EncodeSlackHtmlEntities -ToEncode $Alert.context.condition.allOf[0].threshold
    $portalLink = $Alert.context.portalLink
    
    $slackMessage = @{ 
        channel = "#$($Channel)"
        attachments = @(
            @{
                color = $alertAttachmentColours[$Alert.status]
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

    param(
        [Parameter(Mandatory=$true)]
        [HttpStatusCode] $Status,
        [string] $Body=""
    )


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ 
        StatusCode = $Status
        Body = $Body
    })
}

function Send-MessageToSlack 
{
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

    param(
        [Parameter(Mandatory = $true)]
        [string] $SlackToken,
        [Parameter(Mandatory=$true)]
        [hashtable] $Message
    )

    $serializedMessage = "payload=$($Message | ConvertTo-Json)"

    Invoke-RestMethod -Uri https://hooks.slack.com/services/$($SlackToken) -Method POST -UseBasicParsing -Body $serializedMessage
}

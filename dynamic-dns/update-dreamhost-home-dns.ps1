Start-Transcript -Path "$PSScriptRoot\update-dreamhost-home-dns.log"

try {
    $key = (Get-Content -Path "$PSScriptRoot\dreamhost-api-key.txt" -First 1).Trim()
}
catch {
    Write-Error "Failed to read API key from file: $_"
    exit 1
}

$type = "A"
$record = "home.mattberube.com"
$urlBase = "https://api.dreamhost.com/"
$listUrl = "$($urlBase)?key=$key&cmd=dns-list_records"

function Get-PublicIp {
    try {
        $ip = Invoke-RestMethod -Uri "https://api.ipify.org"
        return $ip
    } catch {
        Write-Error "Failed to retrieve public IP address: $_"
        return $null
    }
}

function Convert-DreamhostDnsList {
    param (
        [string]$listData
    )

    $records = @()
    $lines = $listData -split "`n"
    foreach ($line in $lines) {
        $fields = $line -split "\s+"
        if ($fields.Length -ge 5) {
            $record = @{
                id = $fields[0]
                zone = $fields[1]
                record = $fields[2]
                type = $fields[3]
                value = $fields[4]
            }
            $records += New-Object PSObject -Property $record
        }
    }
    return $records
}

$ip = Get-PublicIp
if ($null -eq $ip) {
    Write-Error "Could not retrieve public IP address. Exiting."
    exit 1
}

Write-Output "Current public IP address: $ip"

$response = Invoke-WebRequest -Uri $listUrl -UseBasicParsing
$records = Convert-DreamhostDnsList -listData $response.Content
$existingRecord = $records | Where-Object { $_.record -eq "$record" -and $_.type -eq $type }

if ($null -ne $existingRecord) {
    if ($existingRecord.value -eq $ip) {
        Write-Output "DNS record is already up to date. No changes needed."
        exit
    }

    $removeUrl = "$($urlBase)?key=$key&cmd=dns-remove_record&record=$record&type=$type&value=$($existingRecord.value)"
    Write-Output "Removing DNS record for address $($existingRecord.value)"
    $response = Invoke-WebRequest -Uri $removeUrl -UseBasicParsing
    Write-Output $response.Content
}

Write-Output "Adding DNS record"
$addUrl = "$($urlBase)?key=$key&cmd=dns-add_record&record=$record&type=$type&value=$ip"
$response = Invoke-WebRequest -Uri $addUrl -UseBasicParsing
Write-Output $response.Content

Stop-Transcript

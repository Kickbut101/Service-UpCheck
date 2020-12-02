
# Service up check
# Going to probably just use some xml file for services to monitor. This would make it easier to add or remove without having to manipulate script
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$homeDir = "C:\Scripts\Service_UpCheck\"
$nameOfXMLFile = "ServicesXMLConfig.xml"

# First time setup, make example xml
if (!(Test-path -path "$homeDir\example.xml"))
    {
        '<opml version="1.1">
<body>
<outline serviceName="Radarr" machineIPorName="192.168.1.1" machinePort="1234" timeoutSeconds="1" externalURL="" expectedReturnCodes="200,401"/>
</body>
</opml>' | Out-File "$homeDir\example.xml"
    }

# Function to reload xml file (in case it is updated whilest still running this script)
# Input: $xmlFileLocation - Literal exact path to xml file.
# output: XML object with xml file contents
function loadXMLFile
    {
        param($xmlFileLocation)
        Clear-Variable XMLFileRaw -ErrorAction SilentlyContinue
        Try {[xml]$XMLFileRaw = Get-Content "$xmlFileLocation" -ErrorAction Stop}
        Catch {Write-host "XMLFile location not found, attempted to read $xmlFileLocation"; pause; exit}
        return($XMLFileRaw)
    }

# Function to loop through all items in the services to check each one
# Input: the xml file data
# Output: $servicesResults - Aggregated data on services - PSObject
function checkServices
    {
        param($xmlFile)
        $servicesData = $xmlFile.opml.body.Outline
        
        $resultArray = @()

        foreach ($service in $servicesData)
            {
                Clear-Variable currentRequestResults,uri,matches,statuscode,isrunning,errorstatus -ErrorAction SilentlyContinue
                $servicesResults = New-Object -TypeName psobject

                # Check the connection type, if externalURL is filled in, this takes priority, otherwise check to see if it's machine name or IP.
                if (!!($service.ExternalURL))
                    {
                        $uri = "$($service.externalURL)"
                    }
                Elseif ($service.machineIPorName -match "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}") 
                    { 
                        $uri = "$($service.machineIPorName):$($service.machinePort)" 
                    }
                Else
                    {
                        $pingData = Test-Connection $service.machineIPorName -Count 1
                        $uri = "$($pingData.IPV4Address):$($service.machinePort)"
                    }

                # Check the connection, check headers
                Try {$currentRequestResults = Invoke-WebRequest -uri "$URI" -method Head -TimeoutSec $($service.timeOutSeconds)}
                Catch {
                            $shush = $($_ -match "\((\d{1,4})\)|(timed out)")
                            if ($matches[1] -ne $null) { $errorStatus = $matches[1] }
                            Else { $errorStatus = $matches[2] }

                      }

                # Save the results
                if (!$service.expectedReturnCodes) # If we don't already define successcodes from the invoke-webrequest
                    { 
                        If ($currentRequestResults.statuscode -eq '200') 
                            {
                                $isRunning = "Running"
                                $StatusCode = "200"
                            } 
                        ElseIF ($errorStatus -like "*timed out*")
                            {
                                $isRunning = "Down"
                                $StatusCode = "Connection timed out"
                            }
                        ELSE 
                            {
                                $isRunning = "Down"
                                $StatusCode = "$($currentRequestResults.statuscode)"
                             }
                    }
                Else
                    {
                        If ($($service.expectedReturnCodes).split(",") -contains $errorStatus -or $($service.expectedReturnCodes).split(",") -contains $currentRequestResults.statuscode) 
                            {
                                $isRunning = "Running"
                                $StatusCode = "$errorStatus"
                            } 
                        ELSE 
                            {
                                $isRunning = "Down"
                                $StatusCode = "$errorStatus"
                            }
                    }
                $servicesResults | Add-Member -MemberType NoteProperty -Name "__ServiceName" -Value $Service.ServiceName
                $servicesResults | Add-Member -MemberType NoteProperty -Name "_ServiceIs" -Value $isRunning
                if (!!$($errorstatus)) {$servicesResults | Add-Member -MemberType NoteProperty -Name "StatusCode" -Value $StatusCode} ELSE {$servicesResults | Add-Member -MemberType NoteProperty -Name "StatusCode" -Value $($currentRequestResults.statuscode)}
                $servicesResults | Add-Member -MemberType NoteProperty -Name "Machine" -Value $service.machineIPorName
                $servicesResults | Add-Member -MemberType NoteProperty -Name "ConnectionTested" -Value $URI
                if ($currentRequestResults.headers.'X-ApplicationVersion') {$servicesResults | Add-Member -MemberType NoteProperty -Name "Version" -Value $currentRequestResults.headers.'X-ApplicationVersion'}
                
                # Add results to list
                $resultArray += $servicesResults
                Clear-Variable servicesResults -ErrorAction SilentlyContinue
            }

        return($resultArray)
    }

# Setup string for output in discord
# Input: powershell object with results
# Output: Output string of the results
function setupString
    {
        param($resultsObject)
        $allproperties = $resultsObject | Get-Member -Type Properties | % name | Sort-Object

        [string]$outputString = ""

        foreach ($service in $resultsObject)
            {
                Foreach ($property in $allproperties)
                    {
                        $outputString += "$($property): $($service.$property) `n"
                    }
                    $outputString += "`n"
            }
         return($outputString)   
    }

$xmlFileLoaded = loadXMLFile -xmlFileLocation $homeDir\$nameOfXMLFile
$fullresults = checkServices -xmlFile $xmlFileLoaded
$discordString = setupString -resultsObject $fullresults

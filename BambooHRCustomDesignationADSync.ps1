param(
    [String]$mode
)

function ErrorCodeType{
    param(
        [String]$ErrorCode
    )

    if($ErrorCode -In 200...299){
        Write-Output "Success"
    }
    elseif ($ErrorCode -In 400...499) {
        Write-Output "User Request Error"
        exit 1
    }
    elseif ($errorCode -In 500...599) {
        Write-Output "Server Error"
        exit -1
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $logFile = "C:\Temp\Logs\DesignationRetrievalLog.txt"
    $logDir = Split-Path -Path $logFile

    if (-Not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory
    }
    $timestamptext = Get-Date -Format "dddd MMMM dd hh:mm tt"
    if($Message -eq " "){
        $logEntry = " "
    }
    else{
        $logEntry = "${timestamptext} : ${Message}"
    }
    Add-Content -Path $logFile -Value $logEntry
    Write-Host $Message -ForegroundColor Yellow
}
function GetEmployeeID{
    param(
        [System.Collections.Hashtable]$headers,
        [String]$UserPrincipalName
    )
    try{
        $response = Invoke-WebRequest -Uri 'https://api.bamboohr.com/api/gateway.php/seafirstinsurance/v1/employees/directory' -UseBasicParsing -Method GET -Headers $headers
        }
        catch {
            if($_.Exception.Response.StatusCode.Value__ -ne "200"){
    
                Write-Log "Directory was not able to be retrieved..."
                exit 1
            }
    }
    $jsonObject = $response.Content | ConvertFrom-Json
    $matchedEmployee = $jsonObject.employees

    $finalID = ""
    foreach($Employee in $matchedEmployee){

        if($Employee.workEmail -eq $UserPrincipalName){
            $finalID = $Employee.id
        }
    }

    return $finalID

}

function GetEmployeeDesignation{
    param(
        [System.Collections.Hashtable]$headers,
        [String]$EmployeeID
    )
    
    try{
    $response = Invoke-WebRequest -Uri "https://api.bamboohr.com/api/gateway.php/seafirstinsurance/v1/employees/${EmployeeID}/tables/customDesignations" -UseBasicParsing -Method GET -Headers $headers
    }
    catch {
        if($_.Exception.Response.StatusCode.Value__ -eq "404"){

            Write-Log "This user does not exist, exiting..."
            exit 1
        }
    }
    
    $jsonObject = $response | ConvertFrom-Json
    $result = ""

    foreach($item in $jsonObject.customDesignationType){
        $result += ", " + $item 
    }
    if($result -eq ", "){
        Write-Log "No Designation Present for user."
    }

    return $result
}

function SetUserAD{
    param(
        [String]$designation,
        [String]$UserPrincipalName
    )

    Set-ADUser -Identity $UserPrincipalName -Replace @{extensionAttribute2=$designation}
    
}
function SetAllUsersADMulti{
    #Grab Active Directory Users
    $Users = Get-ADUser -Filter * | Where-Object { $_.Enabled -eq $true } | Select-object GivenName,UserPrincipalName,SamAccountName

    $UpdateCounter = 0

    #Loop through all users and further filter down
    foreach($user in $Users){
        
        $SingleUserEmailAddress = $user.UserPrincipalName
        #$SingleUserGivenName = $user.GivenName
        $SingleUserSamName = $user.SamAccountName

        #Filters out all users with blank emails and emails that dont have a valid '@seafirstinsurance.com' domain
        if(($SingleUserEmailAddress -ne " ") -and ($SingleUserEmailAddress -match "@seafirstinsurance.com")){

            Write-Log "==============="
            Write-Log "User: ${SingleUserEmailAddress}"
    
            $EmpID = GetEmployeeID -UserPrincipalName $SingleUserEmailAddress -headers $headers
            Write-Log "ID: $EmpID"
            if($EmpID -eq ""){
                Write-Log "User does not exist"
            }
            else{
          
                $designation = GetEmployeeDesignation -headers $headers -EmployeeID $EmpID
                if($designation -eq ""){
                    Write-Log "NO DESIGNATION"
               
                }
                else{
                    Write-Log "Designation: $designation"
                    Write-Log " "
             
                    SetUserAD -designation $designation -UserPrincipalName $SingleUserSamName
                
                }
                $UpdateCounter++
                #Start-Sleep -Seconds 1
            }
        }
    }
    Write-Log "USERS UPDATED: $UpdateCounter"
    Start-adsyncsynccycle -policytype delta

}
function SetAllUsersSingle {
    param(
        [String]$EmployeeUPN,
        [String]$EmployeeSam
    )
    Write-Log "Getting AD User: ${EmployeeUPN}..."
    Write-Log " "
    Write-Log "Getting Employee ID..."
    $EmpID = GetEmployeeID -UserPrincipalName $EmployeeUPN -headers $headers
    Write-Log "ID: $EmpID"
    Write-Log " "
    Write-Log "Getting Designation..."
    $designation = GetEmployeeDesignation -headers $headers -EmployeeID $EmpID
    if($designation -eq ""){
        Write-Log "NO DESIGNATION"
    }
    else{
        Write-Log "Designation: $designation"
        Write-Log " "
        Write-Log "Setting User in AD..."
        SetUserAD -designation $designation -UserPrincipalName $EmployeeSam
        Write-Log "SUCCESS"
    }
    Start-adsyncsynccycle -policytype delta
    
}
function Main{
    param(
        [String]$arg
    )


    Write-Log " "
    Write-Log "======= Start ====="
    Write-Log " "
    #API Key
    $API_KEY = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($env:bamboo_key))
    # Authenticate and setup headers
    $headers=@{}
    $headers.Add("Accept", "application/json")
    $headers.Add("authorization", "Basic $API_KEY")

    #$SingleEmployeeSam = "dbernardes"

    $SingleEmployeeEmail = "aholmwood@seafirstinsurance.com"
    $SingleEmployeeSam = $SingleEmployeeEmail -replace '@.*$'  
    
    switch ($arg){
        "m" { SetAllUsersADMulti
            #Write-Output "SETTING MULTI"
        }
        "s" { SetAllUsersSingle -EmployeeUPN $SingleEmployeeEmail -EmployeeSam $SingleEmployeeSam}
        default {
            Write-Output "No valid argument provided."
            Write-Output "Use either '-mode m' (Multi) or '-mode s' (Single) Parameter when Runing the script" 
            Write-Output "USAGE: script.ps1 -mode s // script.ps1 -mode m"
        }
    }

    Write-Log " "
    Write-Log "======= End ====="
    Write-Log " "
}

Main -arg $mode
    

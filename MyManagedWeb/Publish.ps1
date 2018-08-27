#
# PublishNew.ps1
#
cd ..
if ($myInvocation.MyCommand.CommandType -ne [System.Management.Automation.CommandTypes]::Script) {
	$localPath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
} else {
	$localPath = [System.IO.Path]::GetDirectoryName($psISE.CurrentFile.FullPath)

} 
Write-Host $localPath
cd $localpath

################################################################################

$subid = "4ba71b45-e24d-4f8c-804c-ec0391af1b13"
$ResourceGroup="MyManagementApplication"
$appname = "MyManagedFunctions"
$azureregion = "EastUS"
$storage = "store4bxudj6xo65by3"
$Location = "EAST US"
$appname = "MyManagedWeb"
$zipfilename = "$appname.zip"
$BuildNumber = "1.0"

################################################################################
# Create the webdeploy Zip Package for the FunctionApps
#
################################################################################

$zipfolder = "webdeploypackages"
$appname = Split-Path (get-location).path -Leaf #now dynamicly name the app based on folder name (FunctionAppDemoPS in this case)
$zipfilename = "$appname.zip"

$zipfilename = "$appname.$($BuildNumber).zip"
$Currentzipfilename = "$appname.latest.zip"
$zipsolution = "$appname.csproj"

$cmd1 = ".\publish.bat " + $zipsolution + '  ' + $zipfolder + ' ' + $zipfilename
$cmd2 = ".\publish.bat " + $zipsolution + '  ' + $zipfolder + ' ' + $Currentzipfilename

cmd.exe /c $cmd1
cmd.exe /c $cmd2

ls "..\webdeploypackages\" |  ? {$_.Extension -notcontains '.zip'} | Remove-Item

################################################################################
################################################################################
# Login to Azure
################################################################################
$context = $(Get-AzureRmContext -ErrorAction SilentlyContinue)

if(!$context.Account){
	Write-Host "login"
   Login-AzureRmAccount
	$context = $(Get-AzureRmContext -ErrorAction SilentlyContinue)
	if(!$context.Account){exit}	
}

#Loads Active Directory Authentication Library
function Load-ActiveDirectoryAuthenticationLibrary(){
  $moduleDirPath = [Environment]::GetFolderPath("MyDocuments") + "\WindowsPowerShell\Modules"
  $modulePath = $moduleDirPath + "\AADGraph"
  if(-not (Test-Path ($modulePath+"\Nugets"))) {New-Item -Path ($modulePath+"\Nugets") -ItemType "Directory" | out-null}
  $adalPackageDirectories = (Get-ChildItem -Path ($modulePath+"\Nugets") -Filter "Microsoft.IdentityModel.Clients.ActiveDirectory*" -Directory)
  if($adalPackageDirectories.Length -eq 0){
    Write-Host "Active Directory Authentication Library Nuget doesn't exist. Downloading now ..." -ForegroundColor Yellow
    if(-not(Test-Path ($modulePath + "\Nugets\nuget.exe")))
    {
      Write-Host "nuget.exe not found. Downloading from http://www.nuget.org/nuget.exe ..." -ForegroundColor Yellow
      $wc = New-Object System.Net.WebClient
      $wc.DownloadFile("http://www.nuget.org/nuget.exe",$modulePath + "\Nugets\nuget.exe");
    }
    $nugetDownloadExpression = $modulePath + "\Nugets\nuget.exe install Microsoft.IdentityModel.Clients.ActiveDirectory -Version 2.14.201151115 -OutputDirectory " + $modulePath + "\Nugets | out-null"
    Invoke-Expression $nugetDownloadExpression
  }
  $adalPackageDirectories = (Get-ChildItem -Path ($modulePath+"\Nugets") -Filter "Microsoft.IdentityModel.Clients.ActiveDirectory*" -Directory)
  $ADAL_Assembly = (Get-ChildItem "Microsoft.IdentityModel.Clients.ActiveDirectory.dll" -Path $adalPackageDirectories[$adalPackageDirectories.length-1].FullName -Recurse)
  $ADAL_WindowsForms_Assembly = (Get-ChildItem "Microsoft.IdentityModel.Clients.ActiveDirectory.WindowsForms.dll" -Path $adalPackageDirectories[$adalPackageDirectories.length-1].FullName -Recurse)
  if($ADAL_Assembly.Length -gt 0 -and $ADAL_WindowsForms_Assembly.Length -gt 0){
    Write-Host "Loading ADAL Assemblies ..." -ForegroundColor Green
    [System.Reflection.Assembly]::LoadFrom($ADAL_Assembly[0].FullName) | out-null
    [System.Reflection.Assembly]::LoadFrom($ADAL_WindowsForms_Assembly.FullName) | out-null
    return $true
  }
  else{
    Write-Host "Fixing Active Directory Authentication Library package directories ..." -ForegroundColor Yellow
    $adalPackageDirectories | Remove-Item -Recurse -Force | Out-Null
    Write-Host "Not able to load ADAL assembly. Delete the Nugets folder under" $modulePath ", restart PowerShell session and try again ..."
    return $false
  }
}

#Acquire AAD token
function AcquireToken($mfa){
  $clientID = "1950a258-227b-4e31-a9cf-717495945fc2"
  $redirectUri = "urn:ietf:wg:oauth:2.0:oob"

  $authority = "https://login.windows.net/f833efa0-4c9a-4791-b782-bdedd8197150"
  $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority,$false
  if($mfa)
  {
    $authResult = $authContext.AcquireToken("https://management.core.windows.net/",$ClientID,$redirectUri,[Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Auto, [Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier]::AnyUser, "amr_values=mfa")
    Set-Variable -Name mfaDone -Value $true -Scope Global
  }
  else
  {
    $authResult = $authContext.AcquireToken("https://management.core.windows.net/",$ClientID,$redirectUri,[Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Always)
  }
  if($authResult -ne $null)
  {
    Write-Host "User logged in successfully ..." -ForegroundColor Green
  }
  Set-Variable -Name headerParams -Value @{'Authorization'="$($authResult.AccessTokenType) $($authResult.AccessToken)"} -Scope Global
  Set-Variable -Name assigneeId -Value $authResult.UserInfo.UniqueId -Scope Global
}

Load-ActiveDirectoryAuthenticationLibrary
AcquireToken $true

################################################################################
################################################################################
 Set-AzureRmContext -SubscriptionId $subid  | out-null
 
################################################################################
# Recreate the Zip Package for the managed unlocked
#
################################################################################


# Get storage Context and see if Container Exists

	$acct = Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroup -Name $storage 

	$storagekeys =  Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup -Name $storage 

	$StorageContext = New-AzureStorageContext -StorageAccountName  $storage  -StorageAccountKey $storagekeys[0].Value;

		$Cont = Get-AzureStorageContainer -Context $StorageContext -Name $zipfolder -ErrorAction SilentlyContinue

    #if no container for folder, create one
	if(!$Cont) {
		write-host -f yellow "[create] create $zipfolder folder on $storage  in $Location." 
		New-AzureStorageContainer -Context $StorageContext -Name $zipfolder -Permission Container 
		write-host -f blue "[completed] created $zipfolder folder on $storage  in $Location."                     
	}
	write-host -f blue "Loading $zipfilename"

	ls $("..\$zipfolder\*.zip") | Set-AzureStorageBlobContent -Container $zipfolder  -Context $storageContext -force

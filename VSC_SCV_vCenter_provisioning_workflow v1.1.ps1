#################################################################################################
#################################################################################################
#################################################################################################
############
############ REST API based script to demonstrate vCenter APIs and NetApp APIs for provisioning
############ and data protection workflows
##################################################################################################
##################################################################################################
############  Rahul Sharma ########
############    17/09/2019 ########
##################################################################################################
##################################################################################################
##################################################################################################


### Trust self signed SSL certificate 
Add-Type @"
   using System.Net;
   using System.Security.Cryptography.X509Certificates;
   public class TrustAllCertsPolicy : ICertificatePolicy {
   public bool CheckValidationResult(
   ServicePoint srvPoint, X509Certificate certificate,
   WebRequest request, int certificateProblem) {
      return true;
   }
}
"@
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls12'
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

write-host "Script start" -ForegroundColor Blue -BackgroundColor white 
########################################
#### Variables
#######################################

### Connection variables 
$vscIP="192.168.0.135"        ### NetApp Virtual Storage Console(VSC) IP
$vcIP="vc1"                  ### vCenter IP
$scvIP= "192.168.0.180"      ### NetApp SnapCenter for vSphere IP(SCV)/Data Broker
$esxclusterName ="Cluster1"  ### ESX cluster Name

## Datastore provisioning variables 
$name="NFS_REST_ds01"          ### name of the NFS datastore 
$ds_type="NFS"                 ### Datastores type 
$proto="NFS"                   ### Protocol used to access datastore
$ontapcluster= "cluster1"      ### ONTAP Cluster
$ontapsvm="svm_REST2"               ### ONTAP SVM
$dsSizeMB="81920"              ### Size of datastore in MB
$aggrName= "aggr1_01"

### VM provisioning
$vmname="RESTvm1"             ### New VM Name
$foldername="InsightdemoREST" ### Folder to place VM
$resourcePoolname= "prod1"    ### ResourcePool name
$guestOS= "RHEL_7_64"         ### Guest OS type

## SnapCenter backup provisoning variables
$rgname="REST_RG_ds"          ### Resource Group name for backups with SnapCenter for vSpher(SCV)
$policyname= "daily"          ### Policy to attach to new Resource Group


############################
### Login to NetApp VSC
############################
$headers = @{
   "Accept"       = "application/json"
}

[Hashtable]$cred =@{};
[Hashtable]$cred.Add("vcenterPassword", "<pwd>")
[Hashtable]$cred.Add("vcenterUserName", "administrator@vsphere.local")
$body = $cred | ConvertTo-Json

$uri="https://$($vscIP):8143/api/rest/2.0/security/user/login"

try
{
    write-host "Connect to Virtual Storage Console(VSC)" -BackgroundColor blue
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
    write-host "Connected to VSC with SessionID: $($response.vmwareApiSessionId)" -ForegroundColor green
}
catch
{
    write-host "Unable to login to VSC" $_
}



######################################
#### Read Cluster,SVM, SCP ID from VSC
######################################
$authheaders = @{
 "vmware-api-session-id" = $response.vmwareApiSessionId
   "Accept"       = "application/json"
}
write-host "Reading SCPID , SVM ID and Cluster ID from VSC" -BackgroundColor blue 
$uri_scp="https://$($vscIP):8143/api/rest/2.0/storage/capability-profiles"
$scpprofile = Invoke-RestMethod -Uri $uri_scp -Headers $authheaders -Method GET  -ContentType "application/json" -ErrorAction Stop

foreach($scpobj in $scpprofile.records)
{
#Write-Host $scpobj.name 

if($scpobj.name -match "silver")
{
    $scpobjid=$scpobj.id
    write-host "The SCP profile name and ID: $($scpobj.name) $($scpobj.id)" -ForegroundColor Green
}

}

$uri_storage="https://$($vscIP):8143/api/rest/2.0/storage/clusters"
$storagesystem = Invoke-RestMethod -Uri $uri_storage -Headers $authheaders -Method GET  -ContentType "application/json" -ErrorAction Stop

foreach($clusters in $storagesystem.records)
{
#Write-Host $scpobj.name 

if($clusters.name -match $ontapcluster)
{
    $clusterid=$clusters.id
    write-host " Cluster Name and Cluster ID: $($clusters.name) $($clusters.id)" -ForegroundColor green

}
if($clusters.name -match $ontapsvm)
{
    $svmname=$clusters.name
    $svmid=$clusters.id
    write-host "SVM Name and SVM ID: $($svmname) $($svmid)" -ForegroundColor Green

}
$clusters.name 
}

#break

##############################
#### Login to VC
##############################

#$Credential = Get-Credential

#$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credential.UserName+':'+$Credential.GetNetworkCredential().Password))
$auth = "REVNT1xBZG1pbmlzdHJhdG9yOk5ldGFwcDEh"
$head = @{
  'Authorization' = "Basic $auth"
}
$uri_vc="https://$($vcIP)/rest/com/vmware/cis/session"


try
{
    write-host "Connect to vCenter" -BackgroundColor blue
    $vcresponse = Invoke-WebRequest -Uri $uri_vc -Headers $head -Method POST  -ErrorAction Stop
    $token = (ConvertFrom-Json $vcresponse.Content).value
    $session = @{'vmware-api-session-id' = $token}
    write-host "Connected to vCenter - Login token" $token -ForegroundColor green
}
catch
{
    write-host "Unable to login to VC" $_
}


##############################
## Cluster Moref from vCenter
##############################
$uri_cluster="https://$($vcIP)/rest/vcenter/cluster"
write-host "Read ClusterMoref vCenter" -BackgroundColor blue 
$res_cluster = Invoke-RestMethod -Uri $uri_cluster  -Method GET  -ContentType "application/json" -Headers $session -ErrorAction Stop
foreach ($clusterobj in $res_cluster.value)
{

    If($clusterobj.name -match $esxclusterName)
    {
        $clustermoref= $clusterobj.cluster
        write-host "ESX Cluster object details $($clustermoref)  $($clusterobj.name)" -ForegroundColor Green
    }

}



##############################
### Creating NFS datastore
##############################
$headersnfs = @{
 "vmware-api-session-id" = $response.vmwareApiSessionId
   "Accept"       = "application/json"
}




$nfsrequest=@{
traditionalDatastoreRequest=
@{  
      name = $name
      datastoreType = $ds_type
      protocol= $proto
      profileID= "$scpobjid"
      spaceReserve= "Thin"
      clusterID= $clusterid
      svmID=$svmid
      targetMoref=$clustermoref
      datastoreSizeInMB=$dsSizeMB
      nfsVersion="NFS3"
      vmfsFileSystem=""
      aggrName=$aggrName
      existingFlexVolName=""
      datastoreClusterMoref=""
      
  }
   
}
$bodynfs = $nfsrequest | ConvertTo-Json
write-host "Starting Datastore creation with JSON" -ForegroundColor green
Write-Host $bodynfs -ForegroundColor Gray

Start-Sleep -Seconds 10
$uri_nfs="https://$($vscIP):8143/api/rest/2.0/admin/create/datastore"

try
{
     $responsenfs = Invoke-RestMethod -Uri $uri_nfs -Headers $headersnfs -Method POST -Body $bodynfs -ContentType "application/json" -ErrorAction Stop
     write-host "$($responsenfs.responseMessage) and taskID is : $($responsenfs.taskid)"
}
catch
{
    write-host "Error creating datastore "$_ -ForegroundColor Red
    
}

 #break
###############################
#### Check the status of task
###############################
$uri_task="https://$($vscIP):8143/api/rest/2.0/tasks/$($responsenfs.taskId)"
do
{

$taskstatusnfs = Invoke-RestMethod -Uri $uri_task -Headers $headersnfs -Method GET  -ContentType "application/json" -ErrorAction Stop
Write-Host $taskstatusnfs.StatusMessage  -ForegroundColor DarkYellow
Write-Host "Status: $($taskstatusnfs.status)"
Start-Sleep -Seconds 10

}until( $taskstatusnfs.status -eq "COMPLETE")

write-host "Datastore creation completed" -ForegroundColor Green


Read-Host "Click any key to continue.." 


#### Read Moref
Write-Host "Reading Datastore Moref" -BackgroundColor Blue 
$uri_ds="https://$($vcIP)/rest/vcenter/datastore"
$ds = Invoke-RestMethod -Uri $uri_ds  -Method GET  -ContentType "application/json" -Headers $session -ErrorAction Stop
foreach ($dsobj in $ds.value)
{

    If($dsobj.name -match $name)
    {
        $dsmoref=$dsobj.datastore
        write-host "Datastore name and Moref $($dsobj.name) $($dsmoref)" -ForegroundColor Green
    }

}
###################
###Get Folder 
###################

Write-Host "Reading Folder Moref" -BackgroundColor Blue 
$uri_folder="https://$($vcIP)/rest/vcenter/folder"
$vmfolder = Invoke-RestMethod -Uri $uri_folder  -Method GET  -ContentType "application/json" -Headers $session -ErrorAction Stop
foreach ($folderobj in $vmfolder.value)
{

If($folderobj.name -match $foldername)
{
    $foldermoref=$folderobj.folder
    write-host "Folder name and Moref $($folderobj.name) $($foldermoref)" -ForegroundColor Green
}

}
#####################
## Get resourcepool
######################
Write-Host "Reading ResourcePool Moref" -BackgroundColor Blue 

$uri_res="https://$($vcIP)/rest/vcenter/resource-pool"
$res = Invoke-RestMethod -Uri $uri_res  -Method GET  -ContentType "application/json" -Headers $session -ErrorAction Stop
foreach ($resobj in $res.value)
{

If($resobj.name -match $resourcePoolname)
{
    $rgmoref= $resobj.resource_pool
    write-host "Folder name and Moref $($resobj.name) $($rgmoref)" -ForegroundColor Green
}

}

#########################
########## Create New VM
#########################
write-host "Starting VM Creation" -BackgroundColor Blue
$uri_newvm="https://$($vcIP)/rest/vcenter/vm"

$vmcreate=@{
    spec=@{
    	 name = $vmname
        guest_OS= $guestOS
        placement=@{
            datastore = $dsmoref
            folder = $foldermoref
            resource_pool = $rgmoref
             }
    }
}
$vmbody = $vmcreate | ConvertTo-Json
$vmbody 
try
{
    $response = Invoke-RestMethod -Uri $uri_newvm -Headers $session -Method POST -Body $vmbody -ContentType "application/json"-ErrorAction Stop
    write-host "VM Name $($vmname) created with moref "$response.value  -ForegroundColor Green

}
catch
{
write-host "Unable to create VM " $_
write-host "Script end" -ForegroundColor white 

}

Read-Host "Click any key to continue... "

################################################################################
################### Backup the new VM and Datastore ##########################
################################################################################



###############################
## 1. ########## Connect to SCV
###############################
Write-Host "Connecting to NetApp SCV" -BackgroundColor blue 
$headers = @{
   "Accept"       = "application/json"
}

[Hashtable]$cred =@{};
[Hashtable]$cred.Add("password", "Netapp1!")
[Hashtable]$cred.Add("username", "demo\administrator")
$body = $cred | ConvertTo-Json

$uri="https://$($scvIP):8144/api/4.1/auth/login"

try
{
    $responsescv = Invoke-RestMethod -Uri $uri -Headers $headers -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
    write-host "Successfully connected to SCV  TokenID: $($responsescv.response.token)" -ForegroundColor green
}
catch
{
    write-host "Unable to login to SCV" $_ -ForegroundColor Red
    exit 
}

############################
##2. ######## Get Policy ID
############################

Write-Host "Reading backup policy ID from SCV" -BackgroundColor blue 
$scvtoken = @{
"Accept" = "application/json"
"Token"= $responsescv.response.token
}


$uri_policy="https://$($scvIP):8144/api/4.1/policies"

try
{
$policy_list = Invoke-RestMethod -Uri $uri_policy  -Method GET  -ContentType "application/json" -Headers $scvtoken  -ErrorAction Stop

foreach( $policy in $policy_list.response.policyResponseList)
{

if ( $policy.name -eq $policyname)
{
    $policyid = $policy.id 
    write-host "Policy name $($policy.name) and ID $($policyid)" -ForegroundColor Green
    
    }

}
}
catch
{
write-host "Error reading policy" $_ 
exit 
}



########################
###3. ####### Create new RG
#########################
write-host "Creating new SCV resource group to backup the new datastore" -BackgroundColor blue 

$rgbody=@{
  description = "REST based RG $($name)"
  entities=   @($dsmoref)
  name = $rgname
  spanningDatastores = @{
  spanningType = "EXCLUDE_ALL"
  }
  policies= @(@{
  id = $policyid}
  )
  notification = "NEVER"
  
 
}



$rgbodyjson= $rgbody | ConvertTo-Json
write-host $rgbodyjson -ForegroundColor Gray

$uri_rg="https://$($scvIP):8144/api/4.1/resource-groups"

try
{

    $rg = Invoke-RestMethod -Uri $uri_rg  -Method POST  -ContentType "application/json" -Headers $scvtoken -body $rgbodyjson -ErrorAction Stop
    Write-Host "Successfully created resource group: $($rg.response) $($rg.statusMessage)" -ForegroundColor Green
}
catch
{
    write-host "Error creating RG" $_ 
    exit 
}

start-sleep -Seconds 10 

#############################
####4. ########## Get RG ID
##############################



$scvtoken = @{
"Accept" = "application/json"
"Token"= $responsescv.response.token
}


$uri_rgroups="https://$($scvIP):8144/api/4.1/resource-groups"

try
{
$rgroup_list = Invoke-RestMethod -Uri $uri_rgroups  -Method GET  -ContentType "application/json" -Headers $scvtoken  -ErrorAction Stop

#Write-Host $rgroup_list.response.resourceGroupResponseList
foreach( $rgroup in $rgroup_list.response.resourceGroupResponseList)
{

    if ( $rgroup.name -eq $rgname)
    {
   
        $rgid = $rgroup.id 
         write-host "Retreived RG name and ID $($rgroup.name) $($rgid)"
    }

}
}
catch
{
    write-host "Error reading Resource group $($rgname)" $_ 
}


Read-Host "Click any key to continue.."

######################################
##5. ## Backup the new resource group
######################################
write-host "Starting manual backup of RG " -BackgroundColor blue 

$rgbackup=@{
  policyId = $policyid
  resourceGroupId =   $rgid
  
}

$rgbackupjson= $rgbackup | ConvertTo-Json
write-host $rgbackupjson -ForegroundColor gray 

$scvtoken = @{
"Accept" = "application/json"
"Token"= $responsescv.response.token
}

$uri_rg="https://$($scvIP):8144/api/4.1/resource-groups/backupnow"

try
{
    $rg_backup = Invoke-RestMethod -Uri $uri_rg  -Method POST  -ContentType "application/json" -Headers $scvtoken -body $rgbackupjson -errorAction Stop
    Write-Host "Started Resource Group backup: $($rg_backup.responseMessage)" -ForegroundColor Green
}
catch
{
    write-host "Error calling backup " $_ 
}


############## Finished###############
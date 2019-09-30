##########################################################################################################################
##########################################################################################################################
#################  ONTAP REST workflow for SVM provisioning               ################################################
##########################################################################################################################
#################        Create SVM, LIF, Volume, Export Policy, DR SVM   ################################################
##########################################################################################################################                         
#################              Rahul Sharma - Oct 2019         ###########################################################
##########################################################################################################################
##########################################################################################################################
##########################################################################################################################
##########################################################################################################################
##########################################################################################################################

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

#########################################################################################################
$user="admin"
$pwd="Netapp1!"
$clusterIP="cluster1"
$clusterDRIP="cluster2"
$password = ConvertTo-SecureString $pwd -AsPlainText -Force
$mycred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user,$password
#########################################################################################################


#####################################################
$svmname="svm_REST1"                 ### New SVM Name 
$lifname=$svmname+"_datalif1"        ### LIF Name 
$lifIP="192.168.0.190"               ### LIF IP 
$lifnetmask ="24"                    ### LIF netmask 
$homeport="e0d"                      ### Home port
$homenode="cluster1-01"              ### Home Node
#######################################################


##########################################################
################# Connect to Cluster #####################
##########################################################

 $headers = @{   
 Accept       = "application/json"
 }
  
 $headjson = $headers   
 
 $uri="https://$($clusterIP)/api/cluster" 
 
  try{    
  
      write-host "Connect to ONTAP Cluster " -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri -Headers $headjson -Credential $mycred -Method GET  -ContentType "application/json" -ErrorAction Stop   
      write-host "Connected to Cluster : $($response.name)" -ForegroundColor green
      write-host ($response | Out-String) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to login to ONTAP cluster" $_
   } 

########################################################
############ Read SVM details ##########################
########################################################
    $uri="https://$($clusterIP)/api/svm/svms" 
 
  try{    
  
      write-host "Enumerate SVMs on the cluster " -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri -Headers $headjson -Credential $mycred -Method GET  -ContentType "application/json" -ErrorAction Stop   
      write-host "Connected to Cluster : $($response.name)" -ForegroundColor green
      write-host ($response.records | Out-String) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to login to ONTAP cluster" $_
   } 
###########################################################
########## Read network details ###########################
###########################################################
    $uri="https://$($clusterIP)/api/network/ip/interfaces" 
 
 try{    
  
      write-host "Enumerate LIFs on the cluster " -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri -Headers $headjson -Credential $mycred -Method GET  -ContentType "application/json" -ErrorAction Stop   
      write-host "Connected to Cluster : $($response.name)" -ForegroundColor green
      write-host ($response.records | Out-String) -ForegroundColor Green
 }
 catch
 {  
      write-host "Unable to login to ONTAP cluster" $_
 } 


################################################
############### Create a NAS SVM on prod #######
################################################
$uri="https://$($clusterIP)/api/svm/svms" 
$body=@{
       name =$svmname
       nfs =@{
       enabled="true"}
       dns= @{
domains =@("demo.netapp.com")
servers =@("192.168.0.253")
}

}

$createsvm=$body | ConvertTo-Json
Write-Host $body -ForegroundColor gray 
  try{    
  
      write-host "Creating new SVM " -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri -Headers $headjson -Credential $mycred -Method POST -body $createsvm  -ContentType "application/json" -ErrorAction Stop   
      write-host "SVM Created : $($response.job)" -ForegroundColor green
      write-host ($response.records | Out-String) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create SVM" $_
     exit 
   } 

   Start-Sleep -Seconds 20

##########################################
############## Create LIF
##########################################
$lifcreate= @{
  enabled= "true"
  ip=@{
    address = $lifIP
    netmask = $lifnetmask
  }
  ipspace =@{
    name= "Default"
     }
  location =@{
    auto_revert= "true"
    broadcast_domain = @{
      name = "Default"
     }
    failover = "home_port_only"
    home_port = @{
      name = $homeport
      node =@{
        name = $homenode
      }
      }
      }
  name = $lifname
  scope = "svm"
  service_policy = @{
    name = "default-data-files"
    }
  svm = @{
    name =$svmname
      }
  }
  

  $lifjson=$lifcreate | ConvertTo-Json -Depth 4
  
       $uri_lif="https://$($clusterIP)/api/network/ip/interfaces" 
  write-host $lifjson -ForegroundColor gray 
  try{    
  
      write-host "Creating new LIF $($lifname) on SVM $($svmname)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_lif -Headers $headjson -Credential $mycred -Method POST -body $lifjson  -ContentType "application/json" -ErrorAction Stop   
      write-host "LIF Created : $($response)" -ForegroundColor green
     }
   catch
   {  
     write-host "Unable to create LIF " $_
   } 

start-sleep -Seconds 5


############################################
############### Create Export-Policy rule ##
############################################
$uri_policy="https://$($clusterIP)/api/protocols/nfs/export-policies?name=default&svm.name=$($svmname)"
write $uri_policy 

################ Read policy UUID #########
try
{
$response_policy = Invoke-RestMethod -Uri $uri_policy -Headers $headjson -Credential $mycred -Method GET  -ContentType "application/json" -ErrorAction Stop   

 $response_policy.records | out-string 
$policy_uuid=$response_policy.records.id
write-host $policy_uuid
}
catch
{
write-host "unable to retrive policy "$_
}

$rule=@{
    
      anonymous_user= "65534"
      clients= @(@{
        
          match= "0.0.0.0/0"
        }
      )
      protocols =@(
        "NFS"
      )
      ro_rule =@(
        "sys"
      )
      rw_rule =@(
        "sys"
      )
      superuser =@(
        "sys"
      )
    }
 
 

############### create new rule on the default policy 

$rulejson=$rule | ConvertTo-Json -Depth 4
write-host $rulejson -ForegroundColor gray 
try
{
$uri_rule="https://$($clusterIP)/api/protocols/nfs/export-policies/$($policy_uuid)/rules"
write-host $uri_rule 
$response_policyrule = Invoke-RestMethod -Uri $uri_rule -Headers $headjson -Credential $mycred -Method POST -Body $rulejson  -ContentType "application/json" -ErrorAction Stop  

}
catch
{
write-host "error updating policy rule"$_ 
}

###########################################################
############ Create FlexVol for VM templates ###############
############################################################

     
      $flexVol_template=$svmname+ "_template"
      write-host $flexVol_template

       $uri_flexvol="https://$($clusterIP)/api/storage/volumes" 

       $bodyflexvol=@{
       name =$flexVol_template
       size= "40GB"
       guarantee=@{
       type ="none"
       }
       svm = @{
       name=$svmname
       }
       aggregates= @(@{
       name= "aggr1_01"
       })
        efficiency=@{
            compression= "background"
            dedupe = "background"
        }
        nas = @{
                 export_policy= @{
                 name ="default"
                }
    
                path= "/$($flexvol_template)"
                security_style ="unix"
              }
   
  }
      

  $createFlexVol=$bodyflexvol | ConvertTo-Json

  write-host $createFlexVol
  try{    
  
      write-host "Creating new FlexVol $($flexVol) on SVM $($svmname)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_flexvol -Headers $headjson -Credential $mycred -Method POST -body $createFlexVol  -ContentType "application/json" -ErrorAction Stop   
      write-host "FlexVol Created : $($response.job.uuid)" -ForegroundColor green
      write-host ($response.job) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create FlexVol" $_
   } 
 


 Start-Sleep -Seconds 10

 Read-Host "Press any key "


#########################################################
###############Provision Template datastore using vCenter 
########################################################


$user="demo\administrator"
$pwd="Netapp1!"
$password = ConvertTo-SecureString $pwd -AsPlainText -Force
$myvccred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user,$password
$vcIP="vc1" 

$vc_ps=Connect-VIServer -Server $vcIP -Credential $myvccred -Protocol https
try
{
write-host "Creating Template datastore" -ForegroundColor Blue 
Get-VMHost | New-Datastore -Nfs -NfsHost $lifIP -Path "/$($flexvol_template)" -Name "template_$($svmname)"
}
catch
{
write-host "error creating datastore"$_ 
}
Start-sleep -Seconds 10

Read-Host "Press any key to continue.. "


### VM provisioning
$vmname="RESTvm1_template"             ### New VM Name
$foldername="InsightdemoREST" ### Folder to place VM
$resourcePoolname= "prod1"    ### ResourcePool name
$guestOS= "RHEL_7_64"         ### Guest OS type

$vcIP="vc1"   

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






#### Read Moref
Write-Host "Reading Datastore Moref" -BackgroundColor Blue 
$uri_ds="https://$($vcIP)/rest/vcenter/datastore"
$ds = Invoke-RestMethod -Uri $uri_ds  -Method GET  -ContentType "application/json" -Headers $session -ErrorAction Stop
foreach ($dsobj in $ds.value)
{

    If($dsobj.name -match "template_$($svmname)")
    {
        $dsmoref=$dsobj.datastore
        write-host "Datastore name and Moref $($dsobj.name) $($dsmoref)" -ForegroundColor Green
    }

}
########################################
###Get Folder ##########################
#######################################

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
#######################################
## Get resourcepool####################
#######################################
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


######################################
########## Create New VM##############
######################################
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
write-host $vmbody  -ForegroundColor gray 
try
{
    $response = Invoke-RestMethod -Uri $uri_newvm -Headers $session -Method POST -Body $vmbody -ContentType "application/json"-ErrorAction Stop
    write-host "VM Template Name $($vmname) created with moref "$response.value  -ForegroundColor Green

}
catch
{
write-host "Unable to create VM " $_
write-host "Script end" -ForegroundColor white 

}

Start-Sleep -Seconds 5 



################################################
### Login to NetApp VSC #######################
#################################################


### Connection variables 
$vscIP="192.168.0.35"        ### NetApp Virtual Storage Console(VSC) IP
$headers = @{
   "Accept"       = "application/json"
}

[Hashtable]$cred =@{};
[Hashtable]$cred.Add("vcenterPassword", "Netapp1!")
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


   
###########################################
### Rediscovery storage systems VSC ######
###########################################


$headersdiscover = @{
 "vmware-api-session-id" = $response.vmwareApiSessionId
   "Accept"       = "application/json"
}

$uri_discover="https://$($vscIP):8143/api/rest/2.0/storage/clusters/discover"

try
{
     $responsediscover = Invoke-RestMethod -Uri $uri_discover -Headers $headersdiscover -Method POST -ContentType "application/json" -ErrorAction Stop
     write-host "$($responsediscover.responseMessage) and taskID is : $($responsediscover.taskid)"
}
catch
{
    write-host "Error refereshing storage "$_ -ForegroundColor Red
    exit
}




read-host “Press ENTER to Start DR SVM provisioning ...”


##########################################################
############### Create a NAS SVM on DR SnapMirror #######
##########################################################

$svmname_sm=$svmname+ "_sm"
$uri_svm_sm="https://$($clusterDRIP)/api/svm/svms" 

$body_svm_sm=@{
       name =$svmname_sm
       nfs =@{
       enabled="true"}
       dns= @{
domains =@("demo.netapp.com")
servers =@("192.168.0.253")
}

}

$createsvm_sm=$body_svm_sm | ConvertTo-Json
Write-Host $body -ForegroundColor gray 
  try{    
  
      write-host "Creating new SVM $($svmname_sm)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_svm_sm -Headers $headjson -Credential $mycred -Method POST -body $createsvm_sm  -ContentType "application/json" -ErrorAction Stop   
      write-host "SVM Created : $($response.job)" -ForegroundColor green
      write-host ($response.records | Out-String) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create SVM on DR cluster" $_
     exit 
   } 

   Start-Sleep -Seconds 15




###################################################
############ Create FlexVol for SM  ###############
###################################################

$i=1
$maxcount=1
do{
      
      $flexVol_sm=$svmname_sm+ "_NFS01_REST_sm" + $i
      write-host $flexVol_sm

       $uri_flexvol="https://$($clusterDRIP)/api/storage/volumes" 

       $bodyflexvol_sm=@{
       name =$flexVol_sm
       size= "80GB"
       guarantee=@{
       type ="none"
       }
       svm = @{
       name=$svmname_sm
       }
       type = "dp"
       aggregates= @(@{
       name= "aggr1_01"
       })
        
  }
      

  $createFlexVol_sm=$bodyflexvol_sm | ConvertTo-Json

  write-host $createFlexVol
  try{    
  
      write-host "Creating new FlexVol $($flexVol) on SVM $($svmname)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_flexvol -Headers $headjson -Credential $mycred -Method POST -body $createFlexVol_sm  -ContentType "application/json" -ErrorAction Stop   
      write-host "FlexVol Created : $($response.job.uuid)" -ForegroundColor green
      write-host ($response.job) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create FlexVol" $_
   } 
   $i++
   Write-Host $i
   }while($i -le $maxcount)


###########################################
############## Peer new SVM
###########################################

   
      $uri_peer_create="https://$($clusterDRIP)/api/svm/peers" 

       $svm_peer_create=@{
           
      peer = @{
      cluster =@{
      name=$clusterIP
      }
      svm =@{
      name=$svmname
      }
      }
      applications= @(
      "snapmirror"
      )

      svm=@{
      name=$svmname_sm
      }

      }
    

$peerjsoncreate=$svm_peer_create | ConvertTo-Json -Depth 4
  
  write-host $peerjsoncreate
 
  try{    
  
      write-host "Create new peer " -BackgroundColor blue    
     $response = Invoke-RestMethod -Uri $uri_peer_create -Headers $headjson -Credential $mycred -Method POST -body $peerjsoncreate  -ContentType "application/json" -ErrorAction Stop   
      write-host "SVM Peered : $($response.job)" -ForegroundColor green
   
   }
   catch
   {  
     write-host "Unable to create peering  " $_
   } 

   Start-Sleep -Seconds 15



   Read-Host "Press any key to continue.." 
   exit 

#####################################
########## Create SM relationship####
####################################

   $svmname_sm=$svmname+ "_sm" 
$i=1
$maxcount=1
do{
      
      $flexVol_sm=$svmname_sm+ "_vol" + $i
      $flexVol_src=$svmname+ "_vol" + $i
    write-host "source volume $($flexvol_src)"
            
$uri_svmsm_create="https://$($clusterDRIP)/api/snapmirror/relationships" 
$src_path="$($svmname):$($flexvol_src)"

$dest_path= "$($svmname_sm):$($flexvol_sm)" 


$svm_sm_create=@{
     source= @{
    path=$src_path
    }
     destination= @{
    path=$dest_path
  }
   
  restore="false" 
 policy =@{name="MirrorAllSnapshots"}
}

    

$jsonsvmsmcreate=$svm_sm_create | ConvertTo-Json 
  
 
 
  try{    
  
      write-host "Creating SnapMirror relationship for SM-S $($src_path) to $($dst_path)" -BackgroundColor blue    
       write-host $jsonsvmsmcreate
       write-host $uri_svmsm_create
      $response_sm = Invoke-RestMethod -Uri $uri_svmsm_create -Headers $headjson -Credential $mycred -Method POST -body $jsonsvmsmcreate  -ContentType "application/json" -ErrorAction Stop   
      write-host "SM-S relationship created completed : $($response_sm)" -ForegroundColor green
 
       
 
      start-sleep -Seconds 10

      $response_uuid = Invoke-RestMethod -Uri "$($uri_svmsm_create)?destination.path=$($dest_path)" -Headers  $headjson  -Credential $mycred -Method GET   -ContentType "application/json" -ErrorAction Stop   
      write-host "UUID for SM relationships with destination $($dest_path) is  $($response_uuid.records.uuid)"
      
      
      
      ####################################
      ####Initialize the SM relationship 
      ###################################
      
      
      $sm_init=@{

      state = "snapmirrored"
      }
    start-sleep -Seconds 3
        

      $sm_init_json=$sm_init | ConvertTo-Json
      write-host $sm_init_json
      write-host "REST CAll .. $($uri_svmsm_create)/$($response_uuid.records.uuid)" -BackgroundColor blue 
      write-host "Start SnapMirror initialize.. " -BackgroundColor blue 
    $response_init = Invoke-RestMethod -Uri "$($uri_svmsm_create)/$($response_uuid.records.uuid)/" -Headers $headjson -Credential $mycred -Method PATCH -body $sm_init_json  -ContentType "application/json" -ErrorAction Stop   
      write-host "SM-S relationship initialized : $($response_init)" -ForegroundColor green

   }
   catch
   {  
     write-host "Unable to create SVM-S relationship " $_
   } 

   $i++

}while ( $i -le $maxcount)
  



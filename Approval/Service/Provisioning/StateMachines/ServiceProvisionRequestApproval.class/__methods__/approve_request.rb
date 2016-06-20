#
# Description: This method is executed when the provisioning request is auto-approved
#

$evm.log("info", "Checking for auto_approval")

approval_type = $evm.object['approval_type'].downcase
$evm.log("info", "approval_type: [#{approval_type}]")

if approval_type == 'auto'
  $evm.log("info", "AUTO-APPROVING")
  $evm.root["miq_request"].approve("admin", "Auto-Approved")
end

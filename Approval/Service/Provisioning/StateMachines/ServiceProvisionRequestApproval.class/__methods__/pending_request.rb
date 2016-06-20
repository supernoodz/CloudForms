#
# Description: This method is executed when the provisioning request is NOT auto-approved
#

# Get objects
msg = $evm.object['reason']
$evm.log('info', "Reason: [#{msg}]")

# Raise automation event: request_pending
$evm.root["miq_request"].pending

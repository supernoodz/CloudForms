#
# Description: Placeholder for service request validation
#

$evm.log(:info, $evm.root['user'].normalized_ldap_group)

approval_type = $evm.object['approval_type'].downcase
$evm.log("info", "approval_type: [#{approval_type}]")

$evm.root['ae_result'] = 'error' if approval_type != 'auto'
# unless approval_type == 'auto' $evm.root['ae_result'] = 'error'

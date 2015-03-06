#
# Description: This method upates the provision status.
# Required inputs: status
#

prov   = $evm.root['miq_provision'] || $evm.root['service_template_provision_task']
status = $evm.inputs['status']

$evm.log(:warn, 'miq_provision missing') unless not prov.nil?

# Update Status for on_entry,on_exit
if $evm.root['ae_result'] == 'ok' || $evm.root['ae_result'] == 'error'
  prov.message = status unless prov.nil?
end

#
# Description: This method updates the service provisioning status
# Required inputs: status
#

prov = $evm.root['service_template_provision_task']

# Get status from input field status
status = $evm.inputs['status']

# Update Status for on_entry,on_exit
if $evm.root['ae_result'] == 'ok' || $evm.root['ae_result'] == 'error'
  
  #########################################################
  # Azure stack error
  #########################################################
  
  if $evm.state_var_exist?('request_message')
    request_message = $evm.get_state_var('request_message')
    prov.message = request_message
  else
    prov.message = status
  end
  
end

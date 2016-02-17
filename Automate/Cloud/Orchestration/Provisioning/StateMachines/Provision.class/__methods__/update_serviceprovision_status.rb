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
  
  if $evm.state_var_exist?('status_message')
    status_message = $evm.get_state_var('status_message')
    prov.message = status_message
  else
    prov.message = status
  end
  
end

#
# Description: Post Provisioned
#

# Method for logging
def log(level, message)
  @method = '----- Microsoft Post Provision -----'
  $evm.log(level, "#{@method} - #{message}")
end

# Once new SCVMM hosted VM appears in the VMDB, add it to its parent service

# Determine necessary variables from service_template_provision_task
prov           = $evm.root['service_template_provision_task']
options        = prov.options[:dialog]
vm_host_name   = options[:dialog_option_0_vm_host_name]
owner_email    = options[:dialog_option_0_owner_email]
destination_id = prov.destination_id
parent_service = $evm.vmdb('service').find_by_id(destination_id)

raise 'service_template_provision_task not found' unless not prov.nil?
raise 'parent_service not found' unless not parent_service.nil?

log(:info, "vm_host_name   => #{vm_host_name}")
log(:info, "owner_email    => #{owner_email}")
log(:info, "destination_id => #{destination_id}")
log(:info, "parent_service => #{parent_service.name}")

# Get the VM directly from the VMDB
vm = $evm.vmdb('vm').find_by_name(vm_host_name)

if vm.nil?
  # VM not available yet, set state retry
  log(:info, "VM <#{vm_host_name}> not appeared in VMDB yet, retrying")
  $evm.root['ae_result']         = 'retry'
  $evm.root['ae_retry_interval'] = '1.minute'
  
else
  # VM available, add to parent service
  log(:info, "Adding VM <#{vm_host_name}> to parent service <#{parent_service.name}>")
  vm.add_to_service(parent_service)

end

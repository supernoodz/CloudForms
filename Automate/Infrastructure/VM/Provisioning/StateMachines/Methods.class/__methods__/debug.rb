#
# Description: Check Microsoft VM Provisioned
#

# Method for logging
def log(level, message)
  @method = '----- Microsoft Check Provisioned -----'
  $evm.log(level, "#{@method} - #{message}")
end

# # Once new SCVMM hosted VM appears in the VMDB, add it to the parent service
# vm_host_name   = $evm.root['service_template_provision_task'].options[:dialog][:dialog_option_0_vm_host_name]
# destination_id = $evm.root['service_template_provision_task'].destination_id
# parent_service = $evm.vmdb('service').find_by_id(destination_id)

# raise 'vm_host_name not found'   unless not vm_host_name.nil?
# raise 'destination_id not found' unless not destination_id.nil?
# raise 'parent_service not found' unless not parent_service.nil?

# log(:info, "vm_host_name   => #{vm_host_name}")
# log(:info, "destination_id => #{destination_id}")
# log(:info, "parent_service => #{parent_service}")

# require 'time'
#vm = $evm.vmdb('vm').find_by_name('wednesday17VM')
vm = $evm.root['vm']
#puts vm.ems_custom_keys.inspect
puts vm.send(:evm_owner_email)
puts vm.owner.inspect

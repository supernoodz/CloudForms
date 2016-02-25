#
# Description: chef_post_provision.rb
#
# Steps:
#   1 - Check whether we're provisioning with Chef
#   2 - Apply disk resize based upon specified flavour
#   3 - Start VM and wait for active network
#   4 - Install Chef client and Bootstrap VM


# Validator key, created via Chef Admin UI (Policy > Clients > noodz-validator > Reset Key)
validator_key = <<PEM
-----BEGIN RSA PRIVATE KEY-----
-----END RSA PRIVATE KEY-----
PEM

begin
  require 'rbvmomi'
rescue LoadError
  `gem install rbvmomi`
  require 'rbvmomi'
end

# basic retry logic
def retry_method(retry_time=1.minute)
  $evm.log(:info, "Sleeping #{retry_time}")
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

def exec_command(vim, vm_ref, cmd, args)

  $evm.log(:info, "#{cmd} #{args}")

  guest_auth = RbVmomi::VIM::NamePasswordAuthentication({
    :username => @guest_username,
    :password => @guest_password,
    :interactiveSession => false
  })

  gom = vim.serviceContent.guestOperationsManager
  vm  = vim.searchIndex.FindByUuid(uuid: vm_ref, vmSearch: true)

  prog_spec = RbVmomi::VIM::GuestProgramSpec(
    :programPath      => cmd,
    :arguments        => args,
    :workingDirectory => '/tmp'
  )

  res = gom.processManager.StartProgramInGuest(
    :vm   => vm,
    :auth => guest_auth,
    :spec => prog_spec
  )
end

# Grab the VM object
$evm.log(:info, "vmdb_object_type: #{$evm.root['vmdb_object_type']}")
case $evm.root['vmdb_object_type']
when 'miq_provision'
  prov = $evm.root['miq_provision']
  vm   = prov.vm unless prov.nil?
  chef_environment  = prov.options[:dialog_environment]
  chef_role         = prov.options[:dialog_role]
  chef_flavor       = prov.options[:dialog_flavor]
else
  vm = $evm.root['vm']
  chef_environment  = $evm.root['dialog_environment']
  chef_role         = $evm.root['dialog_role']
  chef_flavor       = $evm.root['dialog_flavor']
end
raise 'VM object is empty' if vm.nil?

unless vm.vendor.downcase == 'vmware'
  $evm.log(:warn, "Only VMware supported currently, exiting gracefully")
  exit MIQ_OK
end

vm_ref          = vm.uid_ems
esx             = vm.ext_management_system.hostname
esx_userid      = vm.ext_management_system.authentication_userid
esx_password    = vm.ext_management_system.authentication_password
chef_server       = $evm.object['chef_server']
@guest_username   = $evm.object['guest_username']
@guest_password   = $evm.object.decrypt('guest_password')

$evm.log(:info, "VM:                #{vm.name}")
$evm.log(:info, "chef_environment:  #{chef_environment}")
$evm.log(:info, "chef_role:         #{chef_role}")
$evm.log(:info, "chef_server:       #{chef_server}")

if chef_server.nil? || chef_environment.nil? || chef_role.nil? || chef_flavor.nil? || @guest_username.nil? || @guest_password.nil?
  # Catch provisioning without Chef
  10.times { $evm.log(:warn, "Required Chef parameters missing, exiting gracefully") }
  exit MIQ_OK
else
  $evm.log(:info, "Chef provision in progress...")
end

###################################
# Resize disk based on specified flavour
###################################

$evm.log(:info, "Resizing disk based on flavour <#{chef_flavor}>")

case chef_flavor
when 'small'
  disk_size = 10
when 'medium'
  disk_size = 15
when 'large'
  disk_size = 20
end

new_disk_size_in_kb = disk_size * (1024**2)
$evm.log(:info, "VM's disk currently #{(vm.disk_1_size.to_i / 1024)} KB, flavour #{new_disk_size_in_kb} KB")

if $evm.state_var_exist?('resize_disk')
  $evm.log(:info, "Disk resize launched, checking status...")

  if new_disk_size_in_kb == (vm.disk_1_size.to_i / 1024)
    $evm.log(:info,"Resizing complete, OK to continue")

  elsif new_disk_size_in_kb <= (vm.disk_1_size.to_i / 1024)
    $evm.log(:warn,"Downsizing not supported, flavour request ignored")

  else
    $evm.log(:info,"Resizing in progress, entering retry...")
    retry_method("15.seconds")
  end
else
  # Launch disk resize
  $evm.log(:info, "Launching disk resize...")
  $evm.instantiate("/Integration/VMware/vCenter/ReconfigVM_ResizeDisk?disk_number=0&disk_size=#{disk_size}")
  $evm.log(:info, "Disk resize launched, entering retry...")
  retry_method("15.seconds")
end

$evm.log(:info, "VM power state: #{vm.power_state}")
if vm.power_state == 'off'
  $evm.log(:info, "Starting VM...")
  vm.start
end

###################################
# Wait until VM is on the network
###################################

unless vm.ipaddresses.empty?
  non_zeroconf = false
  vm.ipaddresses.each do |ipaddr|
    non_zeroconf = true unless ipaddr.match(/^(169.254|0)/)
    $evm.log(:info, "VM:<#{vm.name}> IP Address found #{ipaddr} (#{non_zeroconf})")
  end
  if non_zeroconf
    $evm.log(:info, "VM:<#{vm.name}> IP addresses:<#{vm.ipaddresses.inspect}> present.")
    $evm.root['ae_result'] = 'ok'
  else
    $evm.log(:warn, "VM:<#{vm.name}> IP addresses:<#{vm.ipaddresses.inspect}> not present.")
    retry_method("15.seconds")
  end
else
  $evm.log(:warn, "VM:<#{vm.name}> IP addresses:<#{vm.ipaddresses.inspect}> not present.")
  vm.refresh
  retry_method("15.seconds")
end

if vm.hostnames.empty? || vm.hostnames.first.blank?
  $evm.log(:info, "Waiting for vm hostname to populate")
  vm.refresh
  retry_method("15.seconds")
end

###################################
# Prepare and Bootstrap new VM
###################################

# http://www.rubydoc.info/github/rlane/rbvmomi/RbVmomi/VIM
vim = RbVmomi::VIM.connect(host: esx, user: esx_userid, password: esx_password, insecure: true)

# Install Chef client
$evm.log(:info, "Installing Chef client")
cmd, args   = '/usr/bin/curl', '-L https://www.opscode.com/chef/install.sh | bash'
exec_command(vim, vm_ref, cmd, args)

# Create Chef directory
$evm.log(:info, "Creating /etc/chef")
cmd, args   = '/bin/mkdir', '/etc/chef'
exec_command(vim, vm_ref, cmd, args)

# Create validator key
$evm.log(:info, "Creating validator key")
cmd, args   = '/bin/echo', "'#{validator_key}' > /tmp/chef-validator.pem"
exec_command(vim, vm_ref, cmd, args)

# Bootstrap client
$evm.log(:info, "Bootstrapping Chef client")
# chef-client --server https://EceWTpAPPchf.globalad.org --validation_key /tmp/chef-validator.pem --environment dev --node-name  paultest.mytbwa.com --runlist "recipe[pauldocstest]"
chef_server       = "https://#{chef_server}"
chef_server       = "https://api.opscode.com/organizations/noodz"
# node_name         = "#{vm.name}.mytbwa.com"
node_name         = vm.name
cmd               = '/usr/bin/chef-client'
args              = "--server #{chef_server} --validation_key /tmp/chef-validator.pem\
  --environment #{chef_environment} --node-name #{node_name} --runlist role[#{chef_role}]"
exec_command(vim, vm_ref, cmd, args)
# Debug on VM - /var/chef/cache/chef-stacktrace.out
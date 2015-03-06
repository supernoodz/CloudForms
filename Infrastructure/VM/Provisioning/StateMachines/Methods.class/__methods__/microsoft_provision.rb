#
# Description: Microsoft Provision
#

require 'winrm'

# Method for logging
def log(level, message)
  @method = '----- Microsoft Provision -----'
  $evm.log(level, "#{@method} - #{message}")
end

# @debug = true

prov = $evm.root['miq_provision'] || $evm.root['service_template_provision_task']
options = prov.options[:dialog]
# log(:info, "prov.inspect => #{prov.inspect}") if @debug
log(:info, "options => #{options}")

# There's no VM object so we'll get the credentials directly
ems_microsoft   = $evm.vmdb('ems_microsoft').first
winrm_host      = ems_microsoft.ipaddress
winrm_user      = ems_microsoft.authentication_userid
winrm_password  = ems_microsoft.authentication_password

port ||= 5985
endpoint = "http://#{winrm_host}:#{port}/wsman"
log(:info, "endpoint => #{endpoint}")

transport = 'ssl' # ssl/kerberos/plaintext
opts = {
  :user         => winrm_user,
  :pass         => winrm_password,
  :disable_sspi => true
}
if transport == 'kerberos'
  opts.merge!(
    :realm            => winrm_realm,
    :basic_auth_only  => false,
    :disable_sspi     => false
  )
end
log(:info, "opts => #{opts}") if @debug

# Get the variables from the dialogue
name        = options[:dialog_option_0_vm_host_name]        # :vm_host_name
path        = options[:dialog_option_0_placement_ds_name]   # :placement_ds_name
vm_host     = options[:dialog_option_0_placement_host_name] # :placement_host_name
vm_template = options[:dialog_option_0_src_vm_name]         # :src_vm_id=>[1000000000710, "Blank VM"]
cpu_count   = options[:dialog_option_0_number_of_sockets]   # :number_of_sockets
memory_mb   = options[:dialog_option_0_vm_memory]           # :vm_memory
vlan        = options[:dialog_option_0_vlan]                # :vlan

# Construct the provision VM PowerShell script - Launch asynchronously and return the SCVMM job GUID
script = <<SCRIPT
Import-Module VirtualMachineManager | Out-Null
Get-VMMServer #{winrm_host} | Out-Null
$task = New-SCVirtualMachine -Name '#{name}' -Path '#{path}' -VMHost #{vm_host} -VMTemplate '#{vm_template}' -CPUCount #{cpu_count.to_i} -MemoryMB #{memory_mb.to_i} -RunAsynchronously
'task_GUID=' + $task.MostRecentTaskID
SCRIPT
log(:info, "script => #{script}") if @debug

log(:info, 'Establishing WinRM connection')
connect_winrm = WinRM::WinRMWebService.new(endpoint, transport.to_sym, opts)

log(:info, 'Executing PowerShell')
powershell_return = connect_winrm.powershell(script)

# Process the winrm output
log(:info, "powershell_return => #{powershell_return}") if @debug
powershell_return[:data].each { |array_item|
  log(:info, "#{array_item}") if @debug

  array_item.each { |k, v|
    case k
    
    # Check for errors
    when :stderr
      status = /(.*)Error(.*)/.match(v.strip)
      raise status[0] if status

    # Extract the SCVMM job GUID and set_state_var
    when :stdout
      task_GUID = /^task_GUID=(.*)/.match(v.strip)
      if task_GUID
        log(:info, "SCVMM job => #{task_GUID[1]}")
        $evm.set_state_var('task_GUID', task_GUID[1])
        break
      end

    end
  }
}

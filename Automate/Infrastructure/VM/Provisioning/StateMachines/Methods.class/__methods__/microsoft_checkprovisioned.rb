#
# Description: Microsoft Provision - Check Provisioned (Task, then Reconfigure)
#

require 'winrm'

# Method for logging
def log(level, message)
  @method = '----- Microsoft Check Provisioned -----'
  $evm.log(level, "#{@method} - #{message}")
end

# @debug = true

prov = $evm.root['miq_provision'] || $evm.root['service_template_provision_task']
options = prov.options[:dialog]
log(:info, "prov.inspect => #{prov.inspect}")
log(:info, "options => #{options}")

# There's no VM object so we'll get the credentials from here for the moment
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

# Grab the SCVMM job GUID from get_state_var
if $evm.state_var_exist?('task_GUID')
  task_GUID = $evm.get_state_var('task_GUID')
else
  raise "State variable 'task_GUID' not found"
end

log(:info, 'Checking provisioning SCVMM task')

# Construct the SCVMM job status PowerShell script - Determine the status of the provision VM job using the GUID
script = <<SCRIPT
Import-Module VirtualMachineManager | Out-Null
Get-VMMServer #{winrm_host} | Out-Null
$job = Get-SCJob -ID #{task_GUID}
if ( $job ) {
  if ( $job.Status -eq 'Completed' -and $job.ErrorInfo.Code -eq 'Success' ) { 'Status=Completed' }
  elseif ( $job.Status -eq 'Failed' ) { 'Status=Failed, ' + $job.ErrorInfo.Problem }
  elseif ( $job.Status -eq 'Running' ) { 'Status=Running, Progress ' + $job.Progress }
  else { 'Status=Unsupported status' }
} else { 'Status=Failed, Job matching GUID not found' }
SCRIPT
log(:info, "script => #{script}") if @debug

log(:info, 'Establishing WinRM connection')
connect_winrm = WinRM::WinRMWebService.new(endpoint, transport.to_sym, opts)

log(:info, 'Executing PowerShell')
powershell_return = connect_winrm.powershell(script)

# Process the winrm output
powershell_return[:data].each { |array_item|
  log(:info, "#{array_item}") if @debug

  array_item.each { |k, v|
    case k
    
    # Check for errors
    when :stderr
      task_status = /(.*)Error(.*)/.match(v.strip)
      raise task_status[0] if task_status

    # Extract the SCVMM job status, set state to retry if it's still running
    when :stdout
      task_status = /^Status=(.*)/.match(v.strip)

      if task_status
        log(:info, "Status => #{task_status[1]}")

        if task_status[1] =~ /^Running(.*)/
          log(:info, 'Task still running, will retry')
          $evm.root['ae_result'] = 'retry'
          $evm.root['ae_retry_interval'] = '1.minute'
          exit MIQ_OK

        elsif task_status[1] =~ /^Failed(.*)/
          raise task_status[1]

        elsif task_status[1] =~ /^Completed(.*)/
          log(:info, 'Task completed')

        else
          raise 'Unsupported status'
        end

        break
      end

    end
  }
}

log(:info, 'Configuring VM')

# Construct the configure VM PowerShell script based on dialogue content
script = <<SCRIPT
Import-Module VirtualMachineManager | Out-Null
Get-VMMServer #{winrm_host} | Out-Null
$vm = Get-SCVirtualMachine -Name '#{name}'
$adapter = Get-SCVirtualNetworkAdapter -VM $vm
Set-SCVirtualNetworkAdapter -VirtualNetworkAdapter $adapter -VirtualNetwork '#{vlan}' | Out-Null
Start-VM -VM '#{name}' | Out-Null
'Success'
SCRIPT
log(:info, "script => #{script}") if @debug

log(:info, 'Establishing WinRM connection')
connect_winrm = WinRM::WinRMWebService.new(endpoint, transport.to_sym, opts)

log(:info, 'Executing PowerShell')
powershell_return = connect_winrm.powershell(script)

# Process the winrm output
powershell_return[:data].each { |array_item|
  log(:info, "#{array_item}") if @debug

  array_item.each { |k, v|
    case k

    # Check for errors
    when :stderr
      status = /(.*)Error(.*)/.match(v.strip)
      raise status[0] if status

    # Check for success output string
    when :stdout
      status = /^Success$/.match(v.strip)
      if status
        log(:info, 'Configuration complete')
        break
      end

    end
  }
}

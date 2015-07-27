###################################
#
# CloudForms Automate Method: check_task
#
# Tagging:
#   datastore_low_cost          - Tag all datastores designated as 'low cost'
#   datastore_normal            - Tag all datastores designated as 'normal', that is not 'low cost'
#   vm_archive_retire_enabled   - Archive during retirement enabled, VM must be tagged prior to retirement if archive is required.
#   vm_archive_retire_disabled  - Automated tag used to indicate archive during retirement is disabled.
#   vm_archived_retire_enabled  - Automated tag used to indicate VM is archived and archive during retirement is enabled.
#   vm_archived_retire_disabled - Automated tag used to indicate VM is archived and archive during retirement is disabled.
#
# Process:
#   - Called during retry state following storage_vmotion state.
#   - Via PowerShell, checks status of storage vmotion task and retries
#
# Notes:
#   Tag all datastores in scope as either 'datastore_low_cost' or 'datastore_normal' (see above)
#   Tag any VM as 'vm_archive_retire_enabled' which is to be 'archived' during retirement.
#   Use VM buttons to 'Archive to Low Cost Storage' and 'Retrieve from Low Cost Storage'
#   The term 'archived' in this process, means powered off and moved to 'low cost' storage (tagged as such).
#   During retirement, tagged VMs will be removed from VC inventory but remain on disk and tagged 'retired_<datastore_name>'
#   VMs must be powered off before archived.
#   Email notofications are generated at all stages and sent to the registered owner.
#
###################################

begin

  # Method for logging
  def log(level, message)
    @method = '---------------- check_task ----------------'
    $evm.log(level, "#{@method} | #{message}")
  end

  #############################
  # Send status email
  #############################
  def send_email(vm, status, status_detail)

    @process = 'retrieve' if $evm.root['action'] == 'retrieve'
    @process = 'retire' if $evm.object['action'] == 'retire'

    # Grab owner info
    # owner = $evm.vmdb('user', vm.evm_owner_id) unless vm.evm_owner_id.nil?

    if vm.owner.nil?
      owner_name = ''
      to = nil
      to ||= $evm.object['to_email_address']
    else
      owner_name = vm.owner.name
      to = vm.owner.email
    end

    # vm = $evm.root['vm'] if vm.nil?
    vm_name = vm.name

    # Get from_email_address from model unless specified below
    from = nil
    from ||= $evm.object['from_email_address']

    # Get signature from model unless specified below
    signature = nil
    signature ||= $evm.object['signature']

    case @process
    when 'retrieve'
      subject = "VM Archive Retrieval Request | #{status}"
    when 'retire'
      subject = "VM Archive Retirement Request | #{status}"
    else      
      subject = "VM Archive Request | #{status}"
    end

    # Build email body
    body = "Hello #{owner_name},"
    case @process
    when 'retrieve'
      body += "<br><br>Your archive retrieval request for [#{vm_name}] has #{status.downcase}."
    when 'retire'
      body += "<br><br>Your archive retirement request for [#{vm_name}] has #{status.downcase}."
    else      
      body += "<br><br>Your archive request for [#{vm_name}] has #{status.downcase}."
    end
    body += "<br><br>#{status_detail}."
    body += '<br><br> Regards,'
    body += '<br><br>'
    body += "<br> #{signature}"

    log(:info, "Sending email to <#{to}> from <#{from}> subject: <#{subject}>")

    $evm.execute('send_email', to, from, subject, body)

    log(:info,"Body: #{body}") if @debug

  end

  ################################
  # Tagging VM as required
  ################################
  def tag_vm(vm, ddatastore, process)

    category_name = 'archive_datastore'
    @process = process
    log(:info, "process <#{process}>") if @debug
    log(:info, "ddatastore <#{ddatastore}>") if @debug
    log(:info, "Current tags <#{vm.tags}>")

    ['vm_archived_retire_enabled,VM | Archived and archive on retire enabled',
      'vm_archived_retire_disabled,VM | Archived and archive on retire disabled',
      'vm_archive_retire_enabled,VM | Archive on retire enabled',
      'vm_archive_retire_disabled,VM | Archive on retire disabled'].each do |t|
      t = t.split(',')
      unless $evm.execute('tag_exists?', category_name, t[0])
        log(:info, "Creating <#{category_name}/#{t[0]}> tag")
        $evm.execute('tag_create', category_name, :name => t[0], :description => t[1])
      end
    end

    case @process
    when 'retrieve'

      # If archived_and_retire_enabled then retire_enabled
      if vm.tagged_with?(category_name,'vm_archived_retire_enabled')
        tag_name = 'vm_archive_retire_enabled'
        log(:info, "Tagging VM with <#{category_name}/#{tag_name}>")
        vm.tag_assign("#{category_name}/#{tag_name}")

      elsif vm.tagged_with?(category_name,'vm_archived_retire_disabled')
        tag_name = 'vm_archive_retire_disabled'
        log(:info, "Tagging VM with <#{category_name}/#{tag_name}>")
        vm.tag_assign("#{category_name}/#{tag_name}")
      end

    when 'retire'
      # Tag with datastore for audit purposes (VM will be removed from vCenter so we need to know where the files are)

      # Create new tag if required
      tag_name = "retired_#{ddatastore.downcase}"
      tag_desc = "VM | Retired and Archive to datastore #{ddatastore}"
      unless $evm.execute('tag_exists?', category_name, tag_name)
        log(:info, "Creating <#{category_name}/#{tag_name}> tag")
        $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag_desc}")
      end

      log(:info, "Tagging VM with <#{category_name}/#{tag_name}>")
      vm.tag_assign("#{category_name}/#{tag_name}")

    else  # archive    

      if vm.tagged_with?(category_name,'vm_archive_retire_enabled')
        tag_name = 'vm_archived_retire_enabled'
        log(:info, "Tagging VM with <#{category_name}/#{tag_name}>")
        vm.tag_assign("#{category_name}/#{tag_name}")

      else
        tag_name = 'vm_archived_retire_disabled'
        log(:info, "Tagging VM with <#{category_name}/#{tag_name}>")
        vm.tag_assign("#{category_name}/#{tag_name}")
      end

    end

    log(:info, "Modified tags <#{vm.tags}>")
  end

  #############################
  # Get started...
  #############################

  @debug = true
  @process = nil
  category_name = 'archive_datastore'

  log(:info, 'CloudForms Automate Method Started')

  log(:info, "$evm.root['ae_state_retries']: <#{$evm.root['ae_state_retries']}>")
  log(:info, "$evm.root['we_are_done']: <#{$evm.root['we_are_done']}>")

  if $evm.root['we_are_done']
    # Check whether vmotion was needed\initiated
    log(:info, 'CloudForms Automate Method Ended')
    exit MIQ_OK
  end

  # vm = $evm.root['vm']
  # raise 'The VM object is empty' if vm.nil?

  ##################################################################
  #
  # Look in the current object for a VM
  #
  vm = $evm.object['vm']
  if vm.nil?
    vm_id = $evm.object['vm_id'].to_i
    vm = $evm.vmdb('vm', vm_id) unless vm_id == 0
  end

  #
  # Look in the Root Object for a VM
  #
  if vm.nil?
    vm = $evm.root['vm']
    if vm.nil?
      vm_id = $evm.root['vm_id'].to_i
      vm = $evm.vmdb('vm', vm_id) unless vm_id == 0
    end
  end

  # No VM Found, exit
  raise "VM object not found" if vm.nil?

  log(:info, "vm.name: #{vm.name}") if @debug
  # log(:info, "vm.inspect: #{vm.inspect}")
  
  ##################################################################

  # Get task Id and destination datastore from VM Custom Keys - not ideal but can't use root object as it's not persistent after first retry.
  vi_task_id = vm.custom_get(:vi_task_id)
  destination_datastore = vm.custom_get(:destination_datastore)
  log(:info, "vm.custom_get(:vi_task_id): <#{vm.custom_get(:vi_task_id).inspect}>")
  log(:info, "vm.custom_get(:destination_datastore): <#{vm.custom_get(:destination_datastore).inspect}>")

  # # Grab owner info
  # owner = $evm.vmdb('user', vm.evm_owner_id) unless vm.evm_owner_id.nil?
  # raise 'The owner object is empty' if owner.nil?
  # log(:info, "Owner name: #{owner.name}")

  #############################
  # Check for retire\retrieve action innvocation.
  #############################
  if $evm.object['action'] == 'retire'
    # Retire invoked via URI parameter '?action=retire', so we need to look at $evm.object['action']
    @process = 'retire'

  elsif $evm.root['action'] == 'retrieve'
    # Retrieve invoked via button attribute\value pair, so we need to look at $evm.root['action']
    @process = 'retrieve'

  else
    # Standard archive invoked
    @process = 'archive'
  end
  log(:info, "Processing <#{@process}> request")

  ################################
  # Setup PowerShell
  ################################

  log(:info, "Setting up PowerShell call")

  if !vm.ext_management_system.name | !vm.ext_management_system.type | !vm.ext_management_system.ipaddress | !vm.ext_management_system.authentication_userid | !vm.ext_management_system.authentication_password
    raise 'One or more required vm.ext_management_system attributes missing'
  end

  # Locate Windows proxy
  proxies = $evm.execute('active_miq_proxies')
  proxy = proxies.detect { |p| p.host.platform == 'windows'}
  raise 'Fatal error, could not find an active Windows SmartProxy' if proxy.nil?
  log(:info, "Windows SmartProxy: #{proxy.name}")

  log(:info, 'Checking storage vMotion task state')

  ps_script = <<PS_SCRIPT
$result = @{}

$vi_task_id = '#{vi_task_id}'
if ( !$vi_task_id ) { $result['Action'] = 'no_var' }

else {

  Add-PSSnapin VMware.VimAutomation.Core

  Connect-VIServer -Server #{vm.ext_management_system.ipaddress} -User '#{vm.ext_management_system.authentication_userid}' -Password '#{vm.ext_management_system.authentication_password}'

  $task = Get-Task | where { $_.Id -eq $vi_task_id }

  if ( !$task ) { $result['Action'] = 'no_task' }
  else {
      $result['State'] = $task.State.ToString()
      $result['PercentComplete'] = $task.PercentComplete

      switch ($task.State) {
          Error       { $result['Action'] = 'failed'}
          Queued      { $result['Action'] = 'retry'}
          Running     { $result['Action'] = 'retry'}
          Success     { $result['Action'] = 'complete'}
          default     { $result['Action'] = 'unknown_state'}
      }

  }

  Disconnect-VIServer -Confirm:$false
}

$result
PS_SCRIPT

  #log(:info, "PowerShell: #{ps_script}")
  result_format = "object"
  result = proxy.powershell(ps_script, result_format)
  log(:info, "Powershell result: <#{result.inspect}>")

  result = result.first
  log(:info, "Action          : <#{result[:Action]}>")
  log(:info, "State           : <#{result[:State]}>")
  log(:info, "PercentComplete : <#{result[:PercentComplete]}>")

  case result[:Action]

    when 'retry'
    log(:info, 'Storage vMotion still processing')
    status_detail = "The #{@process} process '#{vi_task_id}' is in progress and #{result[:PercentComplete]}% complete, you will be notified once completed"
    send_email(vm, 'In Progress', status_detail)

    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '2.minute'
    # $evm.root['ae_retry_interval'] = '30.seconds'

    log(:info, "ae_retry_interval #{$evm.root['ae_retry_interval']}")
    log(:info, "ae_state_retries #{$evm.root['ae_state_retries']}")
    $evm.root['vi_task_id'] = vi_task_id
    $evm.root['destination_datastore'] = destination_datastore

    when 'complete'
    log(:info, 'Storage vMotion completed')
    send_email(vm, 'Completed', "The #{@process} process has completed successfully. The new datastore is '#{destination_datastore}'")
    tag_vm(vm, destination_datastore, @process)

    when 'no_task'
    log(:info, 'Storage vMotion failed')
    send_email(vm, 'Failed', "The #{@process} process has failed, task <#{vi_task_id}> was not found in vCenter, check the CloudForms automate.log for details")
    exit MIQ_ERROR

    when 'no_var'
    log(:info, 'Storage vMotion failed')
    send_email(vm, 'Failed', "The #{@process} process failed, task Id <#{vi_task_id}> was not passed to PowerShell, check the CloudForms automate.log for details")
    exit MIQ_ERROR

    when 'unknown_state'
    log(:info, 'Storage vMotion failed')
    send_email(vm, 'Failed', "The #{@process} process failed, task <#{vi_task_id}> is in an unexpected state, check VMware vCenter <#{vm.ext_management_system.name}> for details")
    exit MIQ_ERROR

    else
    log(:info, 'Storage vMotion failed')
    send_email(vm, 'Failed', "The #{@process} process failed, no result 'action' passed from PowerShell, check the CloudForms automate.log for details")
    exit MIQ_ERROR

  end

  ################################
  # Exit method
  ################################

  log(:info, 'CloudForms Automate Method Ended')
  exit MIQ_OK

# Set Ruby rescue behaviour
rescue => err

  log(:error, "Message: #{err.message}")
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  # send_email(vm, 'Failed', "The following error has occurred '#{err.message}'")
  exit MIQ_ABORT

end

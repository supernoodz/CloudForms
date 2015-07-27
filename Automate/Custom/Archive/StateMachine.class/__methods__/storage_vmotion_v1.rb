###################################
#
# CloudForms Automate Method: storage_vmotion
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
#   - Launch from 'archive' or 'retrieve' VM buttons or during VM retirement.
#   - Review storage and vm tagging.
#   - Check existing storage against desired storage.
#   - Invoke PowerShell to move VM asyncronously and return task id.
#   - Update VM custom array with task.
#   - Complete and allow retry state to check task id.
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
#
###################################

begin

  # Method for logging
  def log(level, message)
    @method = '---------------- storage_vMotion ----------------'
    $evm.log(level, "#{@method} | #{message}")
  end

  #############################
  # Factory/VM/unregister_from_vc
  #############################

  def unregister_from_vc(vm)

    @method = 'unregister_from_vc(storage_vMotion_VM)'

    ems = vm.ext_management_system
    $evm.log('info', "Unregistering VM:<#{vm.name}> from EMS:<#{ems ? ems.name : nil}")
    #vm.unregister

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
      tag_desc = "VM | Retired and Archived to datastore #{ddatastore}"
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

  # update_provision_status(status => 'Customizing Request',status_state => 'on_entry')

  @debug = true
  @process = nil
  category_name = 'archive_datastore'

  log(:info, 'CloudForms Automate Method Started')
  
  #############################
  # Check and create the necessary category and tags on the first pass
  #############################

  unless $evm.execute('category_exists?', category_name)
    log(:info, "Creating <#{category_name}> category")
    $evm.execute('category_create', :name => category_name, :single_value => true, :description => 'Archive Datastore')
  end

  ['datastore_low_cost,Datastore | Low Cost Storage',
    'datastore_normal,Datastore | Normal Storage',
    'vm_archived_retire_enabled,VM | Archived and archive-on-retire enabled',
    'vm_archived_retire_disabled,VM | Archived and archive-on-retire disabled',
    'vm_archive_retire_enabled,VM | Archive-on-retire enabled',
    'vm_archive_retire_disabled,VM | Archive-on-retire disabled'].each do |t|
    t = t.split(',')
    unless $evm.execute('tag_exists?', category_name, t[0])
      log(:info, "Creating <#{category_name}/#{t[0]}> tag")
      $evm.execute('tag_create', category_name, :name => t[0], :description => t[1])
    end
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

  # # Grab owner info
  # owner = $evm.vmdb('user', vm.evm_owner_id) unless vm.evm_owner_id.nil?
  # raise 'The owner object is empty' if owner.nil?
  # log(:info, "Owner name: #{owner.name}")

  #############################
  # Check for retire\retrieve action innvocation.
  #############################
  if $evm.object['action'] == 'retire'
    # Check instance for 'action' attribute of 'retire'
    @process = 'retire'
    log(:info, "Processing VM #{vm.name} <#{@process}>, checking VM tagging")

  elsif $evm.root['action'] == 'retrieve'
    # Retrieve invoked via button attribute\value pair, so we need to look at $evm.root['action']
    @process = 'retrieve'
    log(:info, "Processing VM #{vm.name} <#{@process}> request")

  else
    # Standard archive invoked
    @process = 'archive'
    log(:info, "Processing VM #{vm.name} <#{@process}> request")

    # Check whether VM is already archived
    tag_name = 'vm_archived_retire_enabled'
    if vm.tagged_with?(category_name,tag_name)
      status_detail = "VM #{vm.name} is already archived on datastore '#{vm.storage.name}', no action necessary"
      log(:info, "#{status_detail}")
      send_email(vm, 'Completed', status_detail)

      # Update root object
      $evm.root['we_are_done'] = true
      log(:info, "$evm.root['we_are_done']: <#{$evm.root['we_are_done']}>")

      tag_vm(vm, vm.storage.name, @process)
      log(:info, "CloudForms Automate Method Ended")
      exit MIQ_OK
    end 
  end

  # Only powered off machines supported (vMotion will work but solution for powered off machines only)
  log(:info, "vm.power_state: #{vm.power_state}") if @debug
  if vm.power_state != 'off'
    raise "The VM #{vm.name} must be powered off in order to perform archive process" unless @process == 'retire'
  end

  # Only support VMware presently
  raise "EMS Type #{vm.ext_management_system.type} is not currently supported" if vm.ext_management_system.type != 'EmsVmware'

  log(:info, "VM #{vm.name}'s present datastore is: #{vm.storage.name}") unless vm.storage.nil?

  # See if VM has archive/d tag, if present, archive during retirement (don't delete)
  if @process == 'retire'
    if vm.tagged_with?(category_name,'vm_archive_retire_enabled') || vm.tagged_with?(category_name,'vm_archived_retire_enabled')
      log(:info, "VM #{vm.name} is tagged for archive during retirement")

    else
      # log(:info, "Current tags <#{vm.tags}>")

      if vm.tagged_with?(category_name,"retired_#{vm.storage.name.downcase}")
        log(:info, "VM #{vm.name} is already tagged as retired [retired_#{vm.storage.name.downcase}], no action necessary")
        send_email(vm, 'Completed', "No action necessary, the VM is already retired on datastore '#{vm.storage.name}'")

      else
        log(:info, "VM #{vm.name} is not tagged for archive, disks will be deleted during retirement")
        unregister_from_vc(vm)
      end

      # Update root object
      $evm.root['we_are_done'] = true
      log(:info, "$evm.root['we_are_done']: <#{$evm.root['we_are_done']}>")

      log(:info, "CloudForms Automate Method Ended")
      exit MIQ_OK
    end
  end

  ################################
  # Determine suitable datastores
  ################################

  log(:info, "Determining suitable datastores")

  storages = $evm.vmdb('storage').all.sort_by {|obj| obj.free_space}.reverse
  log(:info, "Total storages found: #{storages.count}") if @debug
  raise "Fatal error, no storage found" if storages.nil?

  # vm_storage = $evm.vmdb('storage', vm.storage)

  # Filter storage by required tag
  tag_name = 'datastore_low_cost'
  tag_name = 'datastore_normal' if @process == 'retrieve'
  storages = storages.find_all { |s|
    if s.tagged_with?(category_name,tag_name)
      true
    end
  }
  log(:info, "Storages tagged <#{tag_name}> : #{storages.count}") if @debug

  raise 'Could not find suitable datastore, check datastore tagging' if storages.count == 0

  # Target datastore is first element in array
  destination_datastore = storages[0]
  log(:info, "Destination Datastore: #{destination_datastore.name}")

  # if destination_datastore.name == vm.storage.name
  if destination_datastore.tagged_with?(category_name,tag_name) && vm.storage.tagged_with?(category_name,tag_name)

    status_detail = "The specified VM is already hosted on the desired storage, no action is necessary. The current datastore is '#{vm.storage.name}'"
    log(:info, "#{status_detail}")
    send_email(vm, 'Completed', status_detail)

    tag_vm(vm, vm.storage.name, @process)

    # Update root object
    $evm.root['we_are_done'] = true
    log(:info, "$evm.root['we_are_done']: <#{$evm.root['we_are_done']}>")

  else

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
    # log(:info, "Proxy.inspect #{proxy.inspect}")

    # Kick-off storage vMotion

    log(:info, "Invoking storage vMotion")

    ps_script = <<PS_SCRIPT
$result = @{}

Add-PSSnapin VMware.VimAutomation.Core

Connect-VIServer -Server #{vm.ext_management_system.ipaddress} -User '#{vm.ext_management_system.authentication_userid}' -Password '#{vm.ext_management_system.authentication_password}'

$moveTask = Move-VM '#{vm.name}' -Datastore '#{destination_datastore.name}' -RunAsync

$result['vi_task_id'] = $moveTask.Id

Disconnect-VIServer -Confirm:$false

$result
PS_SCRIPT

    #log(:info, "PowerShell: #{ps_script}") if @debug
    result_format = "object"
    result = proxy.powershell(ps_script, result_format)
    log(:info, "Powershell result: <#{result.inspect}>")

    result = result.first
    vi_task_id = result[:vi_task_id]

    log(:info, "Task ID: <#{vi_task_id}>")

    # Update VM Custom Keys with task Id and destination datastore - not ideal but can't use root object as it's not persistent after first retry.
    vm.custom_set(:vi_task_id, vi_task_id)
    vm.custom_set(:destination_datastore, destination_datastore.name)
    log(:info, "vm.custom_get(:vi_task_id): <#{vm.custom_get(:vi_task_id).inspect}>")
    log(:info, "vm.custom_get(:destination_datastore): <#{vm.custom_get(:destination_datastore).inspect}>")

    status_detail = "The #{@process} process '#{vi_task_id}' has started and may take some time, you will be notified once completed"
    send_email(vm, 'Started', status_detail)

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
  send_email(vm, 'Failed', "The following error has occurred '#{err.message}'")
  exit MIQ_ABORT

end

###################################
#
# CloudForms Automate Method: storage_vmotion_email
#
#   Alert email invoked through control policy where a VM is on Low Cost Storage and should not be powered on
#
###################################

begin

  # Method for logging
  def log(level, message)
    @method = '------------- storage_vmotion_email -------------'
    $evm.log(level, "#{@method} | #{message}")
  end

  #############################
  # Send status email
  #############################
  def send_email()

    vm = $evm.root['vm']
    raise 'The VM object is empty' if vm.nil?

    owner = $evm.vmdb('user', vm.evm_owner_id) unless vm.evm_owner_id.nil?
    if owner.nil?
      owner_name = ''
      to = nil
      to ||= $evm.object['to_email_address']
    else
      owner_name = owner.name
      to = owner.email
    end

    vm = $evm.root['vm'] if vm.nil?
    vm_name = vm.name

    # Get from_email_address from model unless specified below
    from = nil
    from ||= $evm.object['from_email_address']

    # Get signature from model unless specified below
    signature = nil
    signature ||= $evm.object['signature']

    subject = "Power On Request | Denied"

  # Build email body
    body = "Hello #{owner_name},"
    body += "<br><br>Your power on request for [#{vm_name}] has been denied."
    body += "<br><br>The VM is archived on Low Cost Storage and must not be powered on. Move the VM using the 'Retrieve from Low Cost Storage' button and try again."
    body += '<br><br> Regards,'
    body += '<br><br>'
    body += "<br> #{signature}"

    log(:info, "Sending email to <#{to}> from <#{from}> subject: <#{subject}>")

    $evm.execute('send_email', to, from, subject, body)

    log(:info,"Body: #{body}") if @debug

  end

  #############################
  # Get started...
  #############################

  # update_provision_status(status => 'Customizing Request',status_state => 'on_entry')

  @debug = true

  log(:info, 'CloudForms Automate Method Started')

  vm = $evm.root['vm']
  raise 'The VM object is empty' if vm.nil?

  # Send email
  send_email()

  ################################
  # Exit method
  ################################

  log(:info, 'CloudForms Automate Method Ended')
  exit MIQ_OK

# Set Ruby rescue behaviour
rescue => err

  log(:error, "Message: #{err.message}")
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT

end

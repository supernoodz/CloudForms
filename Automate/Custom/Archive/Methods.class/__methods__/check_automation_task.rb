###################################
#
# CloudForms Automate Method: check_automation_task
#
###################################

begin

  # Method for logging
  def log(level, message)
    @method = '---------------- check_automation_task ----------------'
    $evm.log(level, "#{@method} | #{message}")
  end

  @debug = true

  # Check for presence of vm_id supplied as instance attribute
  if $evm.object['vm_id']
    vm_id = $evm.object['vm_id']
    log(:info, "vm_id: #{vm_id}")
  else
    raise "$evm.object['vm_id'] not found"
  end

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

  auto_task_id = vm.custom_get(:auto_task_id).to_i
  log(:info, "auto_task_id: #{auto_task_id}") if @debug

  ##################################################################

  # Require necessary gems
  require 'savon'

  # Set up Savon client
  client = Savon::Client.new do |wsdl, http|
    wsdl.document = "https://#{$evm.root['miq_server'].ipaddress}/vmdbws/wsdl"
    http.auth.basic 'admin', 'smartvm'
    http.auth.ssl.verify_mode = :none
  end

  # Build has of paramters
  body_hash = {}
  body_hash['requestId']  = "#{auto_task_id}"
  log(:info, "body_hash: #{body_hash}")

  response = client.request :get_automation_request do |soap|
    soap.body = body_hash
  end

  request_hash = response.to_hash
  log(:info, "Request Returned: #{request_hash.inspect}")

  request_state = request_hash[:get_automation_request_response][:return][:request_state]
  message       = request_hash[:get_automation_request_response][:return][:message]
  status        = request_hash[:get_automation_request_response][:return][:status]
  log(:info, "Automation Request request_state: #{request_state}")
  log(:info, "Automation Message: #{message}")
  log(:info, "Automation Status: #{status}")

  if request_state.match('pending|queued|active')
    log(:info, 'Request not completed, request_statemachine will retry')
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '2.minute'

  elsif request_state == 'finished'
    log(:info, 'Request has completed')

  else
    raise 'Unexpected request request_state'
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
  exit MIQ_ABORT

end

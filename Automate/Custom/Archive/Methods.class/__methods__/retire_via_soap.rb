###################################
#
# CloudForms Automate Method: retire_via_soap
#
###################################

begin

  # Method for logging
  def log(level, message)
    @method = '---------------- retire_via_soap ----------------'
    $evm.log(level, "#{@method} | #{message}")
  end

  # # Check for presence of vm_id supplied as instance attribute
  # if $evm.object['vm_id']
  #   vm_id = $evm.object['vm_id']
  #   log(:info, "vm_id: #{vm_id}")
  # else
  #   raise "$evm.object['vm_id'] not found"
  # end

  vm = $evm.root['vm']
  raise 'The VM object is empty' if vm.nil?
  vm_id = vm.id
  log(:info, "vm_id: #{vm_id}")

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
  body_hash['version']    = '1.1'
  body_hash['uri_parts']  = 'namespace=ZCustom/Archive|class=StateMachine|instance=retire|message=create'
  body_hash['parameters'] = "vm_id=#{vm_id}"
  body_hash['requester']  = 'auto_approve=true'
  log(:info, "body_hash: #{body_hash}")

  response = client.request :create_automation_request do |soap|
    soap.body = body_hash
  end

  request_hash = response.to_hash
  log(:info, "Request Returned: #{request_hash.inspect}")

  auto_task_id = request_hash[:create_automation_request_response][:return]
  log(:info, "Automation Request Id: #{auto_task_id}")

    # Update VM Custom Key automation task id
    vm.custom_set(:auto_task_id, auto_task_id.to_s)
    log(:info, "vm.custom_get(:auto_task_id): <#{vm.custom_get(:auto_task_id)}>")

    # log(:info, 'Sleep for a minute....')
    # sleep(1.minutes)

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

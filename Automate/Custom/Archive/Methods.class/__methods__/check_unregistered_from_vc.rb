###################################
#
# EVM Automate Method: check_unregistered_from_vc
#
# Notes: This method checks to see if the VM is unregistered from the VC
#
###################################
begin
  @method = 'check_unregistered_from_vc'
  $evm.log("info", "#{@method} - EVM Automate Method Started")

  # Turn of verbose logging
  @debug = true

  vm = $evm.root['vm']

  unless vm.nil?

    category_name = 'archive_datastore'
    tag_name = "retired_#{vm.storage.name.downcase}"
    $evm.log("info", "#{@method} - Tag Name: #{tag_name}")

    if vm.tagged_with?(category_name,tag_name)
      $evm.log("info", "#{@method} - VM tagged [#{category_name}/#{tag_name}], skipping check")

    else
      if !vm.registered?
        # Bump State
        $evm.log('info', "#{@method} - VM:<#{vm.name}> has been unregistered from EMS") if @debug
        $evm.root['ae_result'] = 'ok'
      else
        $evm.log('info', "#{@method} - VM:<#{vm.name}> is on Host:<#{vm.host}>, EMS:<#{vm.ext_management_system.name}>") if @debug
        $evm.root['ae_result']         = 'retry'
        $evm.root['ae_retry_interval'] = '15.seconds'
      end
    end

  end

  #
  # Exit method
  #
  $evm.log("info", "#{@method} - EVM Automate Method Ended")
  exit MIQ_OK

  #
  # Set Ruby rescue behavior
  #
rescue => err
  $evm.log("error", "#{@method} - [#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

#
# Description: This method checks to see if the stack has been provisioned
#   and whether the refresh has completed
#

def refresh_provider(service)
  provider = service.orchestration_manager

  $evm.log("info", "Refreshing provider #{provider.name}")
  $evm.set_state_var('provider_last_refresh', provider.last_refresh_date.to_i)
  provider.refresh
end

def refresh_may_have_completed?(service)
  provider = service.orchestration_manager
  provider.last_refresh_date.to_i > $evm.get_state_var('provider_last_refresh')
end

def check_deployed(service)
  $evm.log("info", "Check orchestration deployed")
  # check whether the stack deployment completed
  status, reason = service.orchestration_stack_status
  case status.downcase
  when 'create_complete'
    $evm.root['ae_result'] = 'ok'
  when 'rollback_complete', 'delete_complete', /failed$/, /canceled$/
    $evm.root['ae_result'] = 'error'
    $evm.root['ae_reason'] = reason
  else
    # deployment not done yet in provider
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '1.minute'
    return
  end

  $evm.log("info", "Stack deployment finished. Status: #{$evm.root['ae_result']}, reason: #{$evm.root['ae_reason']}")
  $evm.log("info", "Please examine stack resources for more details") if $evm.root['ae_result'] == 'error'

  #########################################################
  # Azure stack error
  #########################################################

  if $evm.root['ae_result'] == 'error' && service.orchestration_manager.type == "ManageIQ::Providers::Azure::CloudManager"

    $evm.log(:info, "Azure stack failure detected")
    require 'azure-armrest'
    require 'pp'
    require 'rest-client'

    conf = Azure::Armrest::ArmrestService.configure(
      :client_id  => service.orchestration_manager.authentication_userid,
      :client_key => service.orchestration_manager.authentication_password,
      :tenant_id  => service.orchestration_manager.uid_ems
    )

    stack_name      = service.stack_name
    # stack_name      = service.options[:stack_name]
    resource_group  = service.options[:create_options][:resource_group]
    raw_stack       = Azure::Armrest::TemplateDeploymentService.new(conf).get(stack_name, resource_group)
    correlation_id  = raw_stack.properties.correlation_id
    $evm.log(:info, "Stack: #{stack_name}, Resource Group: #{resource_group}, Correlation Id: #{correlation_id}")

    event_service   = Azure::Armrest::Insights::EventService.new(conf)
    date            = (Time.now - 86400).httpdate
    filter          = "eventTimestamp ge #{date} and correlationId eq #{correlation_id}"
    select          = 'correlationId, Properties'
    events          = event_service.list(filter, select)

    events.each { |event|
      code = nil; message = nil
      if event.respond_to?(:properties)
        if event.properties.respond_to?(:status_message)
          $evm.log(:error, event.properties.status_message)
          if event.properties.status_message =~ /error/i
            status_message  = JSON.parse(event.properties.status_message)
            unless status_message['error'].nil?
              if status_message['error']['details'].blank?
                code    = status_message['error']['code']
                message = status_message['error']['message'].gsub(/[^a-zA-Z0-9\-\s],/, '')
              elsif status_message['error']['details'].empty?
                code    = status_message['error']['code']
                message = status_message['error']['message'].gsub(/[^a-zA-Z0-9\-\s],/, '')
              else
                code    = status_message['error']['details'][0]['code']
                message = status_message['error']['details'][0]['message'].gsub(/[^a-zA-Z0-9\-\s],/, '')
              end
              $evm.log(:error, "#{code}: #{message}")  
              status_message  = "#{code}: #{message}".truncate(255)
              $evm.set_state_var('status_message', status_message)
              break
            end
          end
        end
      end
    }

  end

  #########################################################
  # Azure stack error
  #########################################################

  return unless service.orchestration_stack
  $evm.set_state_var('deploy_result', $evm.root['ae_result'])
  $evm.set_state_var('deploy_reason', $evm.root['ae_reason'])

  refresh_provider(service)

  $evm.root['ae_result']         = 'retry'
  $evm.root['ae_retry_interval'] = '30.seconds'
end

def check_refreshed(service)
  $evm.log("info", "Check refresh status of stack (#{service.stack_name})")

  if refresh_may_have_completed?(service)
    $evm.root['ae_result'] = $evm.get_state_var('deploy_result')
    $evm.root['ae_reason'] = $evm.get_state_var('deploy_reason')
    $evm.log("info", "Refresh completed.")
  else
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '30.seconds'
  end
end

@status_message = nil
task = $evm.root["service_template_provision_task"]
service = task.destination
if $evm.state_var_exist?('provider_last_refresh')
  check_refreshed(service)
else
  check_deployed(service)
end

if $evm.state_var_exist?('status_message')
  status_message = $evm.get_state_var('status_message')
  task.miq_request.user_message = status_message
else
  task.miq_request.user_message = $evm.root['ae_reason'].truncate(255) unless $evm.root['ae_reason'].blank?
end

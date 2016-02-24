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
    resource_group  = service.options[:create_options][:resource_group]
    raw_stack       = Azure::Armrest::TemplateDeploymentService.new(conf).get(stack_name, resource_group)
    correlation_id  = raw_stack.properties.correlation_id
    $evm.log(:info, "Stack: #{stack_name}, Resource Group: #{resource_group}, Correlation Id: #{correlation_id}")

    event_service   = Azure::Armrest::Insights::EventService.new(conf)
    date            = (Time.now - 86400).httpdate
    filter          = "eventTimestamp ge #{date} and correlationId eq #{correlation_id}"
    select          = 'correlationId, Properties'
    events          = event_service.list(filter, select)

    @request_message = nil
    events.each do |event|
      code = nil; message = nil

      if event.respond_to?(:properties)
        if event.properties.respond_to?(:status_code)
          $evm.log(:info, "status_code => #{event.properties.status_code}")

          if event.properties.respond_to?(:status_message)
            $evm.log(:info, "status_message => #{event.properties.status_message}")

            case event.properties.status_code.downcase

            when 'conflict'

              status_message  = JSON.parse(event.properties.status_message)
              $evm.log(:error, "status_message => #{status_message}")

              code    = status_message['Code']
              message = status_message['Message'].gsub(/[^a-zA-Z0-9\-\s],/, '')

              @request_message  = "#{code}: #{message}"
              break
            
            when 'badrequest'
              
              status_message  = JSON.parse(event.properties.status_message)
              $evm.log(:error, "status_message => #{status_message}")

              unless status_message['error'].nil?
                if status_message['error']['details'].blank?
                  code    = status_message['error']['code']
                  message = status_message['error']['message']

                elsif status_message['error']['details'].empty?
                  code    = status_message['error']['code']
                  message = status_message['error']['message']

                else
                  code    = status_message['error']['details'][0]['code']
                  message = status_message['error']['details'][0]['message']
                end
                message = message.gsub(/[^a-zA-Z0-9\-\s],/, '')

                @request_message  = "#{code}: #{message}"
                break
              end

            else
              $evm.log(:info, "Ignoring status_code #{event.properties.status_code}")
            end

          else
            $evm.log(:info, "Ignoring empty status_message")
          end

        end
      end
      @request_message  = "Error: Stack error detected but detail not found"
    end

    @request_message = @request_message.truncate(255) if @request_message.respond_to?(:truncate)
    $evm.log(:error, @request_message)
    $evm.set_state_var('request_message', @request_message)

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

if $evm.state_var_exist?('request_message')
  request_message = $evm.get_state_var('request_message')
  task.miq_request.user_message = request_message
else
  task.miq_request.user_message = $evm.root['ae_reason'].truncate(255) unless $evm.root['ae_reason'].blank?
end

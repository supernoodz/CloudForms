#
# Description: Post Slack Message
#

# gem install gli
# gem install slack-ruby-client

def log(level, message)
  $evm.log(level, message)
end

def sanitise_message(message)
  message.gsub(/(?:[0-9]{1,3}\.){3}[0-9]{1,3}/, "REDACTED")
end

require 'rest-client'
require 'slack-ruby-client'

proxy_server   = $evm.object['proxy_server']
proxy_port     = $evm.object['proxy_port']
proxy_user     = $evm.object['proxy_user']
proxy_password = $evm.object.decrypt('proxy_password')
slack_channel  = $evm.object['slack_channel']
slack_token    = $evm.object.decrypt('slack_token')

proxy_url      = "https://#{proxy_user}:#{proxy_password}@#{proxy_server}:#{proxy_port}" unless proxy_server.nil?

Slack::Web::Client.configure do |config|
  config.token = slack_token
  config.proxy = proxy_url unless proxy_server.nil?
end

client = Slack::Web::Client.new
client.auth_test

log(:info, "$evm.parent: #{$evm.parent}")
event_stream = $evm.root['event_stream']
log(:info, event_stream.full_data)

unless event_stream.nil?
  data = event_stream.full_data
  unless data.nil?
   if data[:event_type].match(/(^node)/i)
      text = "#{data[:event_type]} (#{data[:timestamp]}) \n\t| #{data[:kind]}: #{data[:name]} "
      text += "| Container: #{data[:container_name]}" unless data[:container_name].nil?
      text += "| Message: #{sanitise_message(data[:message])}" unless data[:message].nil?
      client.chat_postMessage(channel: slack_channel, text: "#{text}", as_user: true)
   end
  end   
end

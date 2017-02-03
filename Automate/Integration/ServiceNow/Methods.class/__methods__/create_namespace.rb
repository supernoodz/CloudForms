#
# Description: Create Service Now CMDB Record for new OCP Namespaces
#

# - Check for existing OCP namespace/project ServiceNow record
# - Create new record if one doesn't exist...

require 'rest-client'
require 'base64'

def log(level, message)
  $evm.log(level, message)
end

def query_record(url, namespace, owner)
  log(:info, "#{__callee__}: #{namespace}")

  url = "#{url}?sysparm_query=name=#{namespace}&sysparm_fields=name,owned_by,sys_id"
  # url = "#{url}?sysparm_query=owned_by=#{owner}&sysparm_fields=name,owned_by,sys_id"
  log(:info, "url: #{url}")

  rest_result = RestClient::Request.new(
    :method   => :get,
    :url      => url,
    :headers  => @headers
  ).execute
  log(:info, "Return code: #{rest_result.code}")

  json_parse = JSON.parse(rest_result)
  result     = json_parse['result']
  log(:info, "result.count: #{result.count}")
  result.each do | r |
    log(:info, "result: #{r}")
  end
  # log(:info, "result: {result}")

 case result.count
  when 0
    return true
  when 1
    return false
  else
    raise "More than one record found"
  end
end

def create_record(url, namespace, owner)
  log(:info, "#{__callee__}: #{namespace}")

  payload = {
    # :active => 'false',
    :description        => "#{namespace} created by #{owner}",
    # :short_description  => 'Cannot read email',
    :name               => namespace,
    :owned_by           => owner
  }
  log(:info, "url: #{url}")
  log(:info, "payload: #{payload}")

  rest_result = RestClient::Request.new(
    :method  => :post,
    :url     => url,
    :headers => @headers,
    :payload => payload.to_json
  ).execute
  log(:info, "Return code: #{rest_result.code}")

  json_parse = JSON.parse(rest_result)
  result     = json_parse['result']
  log(:info, "result: #{result}")
end

#
# Do stuff...
#

# Service Now
snow_server   = $evm.object['snow_server']
snow_user     = $evm.object['snow_user']
snow_password = $evm.object.decrypt('snow_password')
snow_table    = $evm.object['snow_table']
url           = "https://#{snow_server}/api/now/table/#{snow_table}"

@headers = {
  :content_type  => 'application/json',
  :accept        => 'application/json',
  :authorization => "Basic #{Base64.strict_encode64("#{snow_user}:#{snow_password}")}"
}

# Proxy
proxy_server   = $evm.object['proxy_server']
proxy_port     = $evm.object['proxy_port']
proxy_user     = $evm.object['proxy_user']
proxy_password = $evm.object.decrypt('proxy_password')
RestClient.proxy = "https://#{proxy_user}:#{proxy_password}@#{proxy_server}:#{proxy_port}" unless proxy_server.nil?

# Process projects/namespaces

# https://bugzilla.redhat.com/show_bug.cgi?id=1378190
# https://github.com/ManageIQ/manageiq/pull/12863

$evm.vmdb(:ContainerProject).where("deleted_on is null").each do |cp|

  log(:info, "Namespace: #{cp.name}")
  
  owner = nil
  #log(:info, "Tags: #{cp.tags}")
  cp.tags.select do |tag|
    #log(:info, "Tag: #{tag}")
    owner_match = tag.match(/container_project:owner\/(\w+)/)
    unless owner_match.nil?
      owner = owner_match[1]
      #log(:info, "Owner: #{owner}")
      break
    end
  end
  
  # owner = get_owner(cp.name)
  if owner.nil?
    log(:warn, "#{cp.name} owner label (tag) not found")
    next
  else
    log(:info, "Owner: #{owner}")
  end

  if query_record(url, cp.name, owner)
    create_record(url, cp.name, owner)
  else
    log(:info, "Record already present")
  end

  # Add sys_id to Project object??
  # vm.custom_set(:servicenow_sys_id, result['sys_id'])

  sleep 1
end
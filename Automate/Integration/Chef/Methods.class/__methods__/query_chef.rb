# Chef API Requirements - https://docs.chef.io/api_chef_server.html#requirements
# Ruby (requires Chef client to be installed) - https://docs.chef.io/auth.html#ruby
# Curl example - https://docs.chef.io/auth.html#curl

require 'openssl'
require 'base64'
require 'time'
require 'rest-client'

debug         = true
user_name     = $evm.object['user_name']
query         = $evm.root['query'] || $evm.object['query']
organisation  = $evm.object['organisation']
chef_server   = $evm.object['chef_server']
# rsa_key       = $evm.object['private_key']

# This is the admin (user_name) user's private key, downloaded from Chef UI
rsa_key = <<PEM
-----BEGIN RSA PRIVATE KEY-----
-----END RSA PRIVATE KEY-----
PEM

$evm.log(:info, "user_name:     #{user_name}")
$evm.log(:info, "query:         #{query}")
$evm.log(:info, "organisation:  #{organisation}")
$evm.log(:info, "chef_server:   #{chef_server}")

user = $evm.root['user']
group_name = user.current_group.description
group_tags = user.current_group.tags
$evm.log(:info, "group_name: #{group_name}")
$evm.log(:info, "group_tags: #{group_tags}")

endpoint        = "/organizations/#{organisation}/#{query}"
chef_server_url = "https://#{chef_server}/organizations/#{organisation}/#{query}"
timestamp       = Time.now.utc.iso8601

# Path of the request: /organizations/NAME/name_of_endpoint, hashed using SHA1 and encoded using Base64
digest      = OpenSSL::Digest::SHA1.digest(endpoint)
hashed_path = Base64.encode64(digest).chop
raise "hashed_path is empty" if hashed_path.nil?

# The body of the request, hashed using SHA1 and encoded using Base64
digest      = OpenSSL::Digest::SHA1.digest('')
hashed_body = Base64.encode64(digest).chop
raise "hashed_body is empty" if hashed_body.nil?

# Canonical header should be encoded in the following format:
canonical_header  = "Method:GET\nHashed Path:#{hashed_path}\nX-Ops-Content-Hash:#{hashed_body}\nX-Ops-Timestamp:#{timestamp}\nX-Ops-UserId:#{user_name}"
key               = OpenSSL::PKey::RSA.new(rsa_key.strip)
encrypted_request = Base64.encode64(key.private_encrypt(canonical_header))
raise "encrypted_request is empty" if encrypted_request.nil?

# Base64 encoding should have line breaks every 60 characters.
header_hash = {}
encrypted_request_lines = encrypted_request.split(/\n/)
encrypted_request.split(/\n/).each_index { |idx|
  if encrypted_request_lines[idx]
    key = "x_ops_authorization-#{idx + 1}".to_sym
    header_hash[key] = encrypted_request_lines[idx]
  end
}

# Authentication headers
header_hash[:accept]                 = 'application/json'
header_hash[:content_type]           = 'application/json'
header_hash[:host]                   = chef_server
header_hash[:x_chef_version]         = '0.10.4'
header_hash[:x_ops_content_hash]     = hashed_body
header_hash[:x_ops_server_api_info]  = '1'
header_hash[:x_ops_sign]             = 'version=1.0'
header_hash[:x_ops_timestamp]        = timestamp
header_hash[:x_ops_userid]           = user_name
# header_hash.each { |k, v| $evm.log(:info, "#{k}: #{v}") }

# Connect to Chef API
response = RestClient::Request.new(
    :method   => :get,
    :url      => chef_server_url,
    :headers  => header_hash,
).execute
# $evm.log(:info, "response.code: #{response.code}") if debug
json_parse = JSON.parse(response)
$evm.log(:info, "json_parse: #{json_parse}") if debug

# Populate the dynamic drop down list object
values = {}
json_parse.each { |a,b|
  $evm.log(:info, "#{a}: #{b}") if debug
  case query

  when /^environments$/  # environments
    values[a] = a unless a =~ /_default/

  when /^roles$/  # roles
    # next unless a.downcase =~ /^cftest-/

    ###################################
    # Filter roles based on user's group
    ###################################

    # Add necessary filter code here...

    values[a] = a
    
  when /^users$/  # users
    a.each { |k,v| v.each { |l,w| values[w] = w } }

  when /^roles\// # roles/whatever
    # Needs to be comma delimited string
    values[b] = b.join(',') if a == 'run_list'

  else
    raise 'Unsupported query'
  end
}
$evm.log(:info, "values: #{values}") if debug

if values.empty?
  values['!'] = 'None available'
else
  values['!'] = '< Select >'
end

list_values = {
  'sort_by'    => :value,
  'data_type'  => :string,
  'required'   => true,
  'values'     => values,
}
list_values.each do |key, value| 
  $evm.object[key] = value
end

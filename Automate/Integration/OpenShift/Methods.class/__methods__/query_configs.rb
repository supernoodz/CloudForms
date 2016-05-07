require 'rest-client'

ose_host          = $evm.object['ose_host']
ose_port          = $evm.object['ose_port']
token             = $evm.object.decrypt('ose_pwd')
project           = $evm.root['dialog_project']

config_list = {}

url = "https://#{ose_host}:#{ose_port}"

query = "/oapi/v1/namespaces/#{project}/deploymentconfigs"
$evm.log(:info, query)

unless project.nil?
  rest_return = RestClient::Request.execute(
    method: :get,
    url: url + query,
    :headers => {
      :accept => :json,
      :authorization => "Bearer #{token}"
    },
    verify_ssl: false)
  result = JSON.parse(rest_return)

  result['items'].each { |i| config_list[i['metadata']['name']] = i['metadata']['name'] }
end

config_list[nil] = config_list.empty? ? "<None>" : "<Choose>"

dialog_field = $evm.object

# sort_by: value / description / none
dialog_field["sort_by"] = "description"

# sort_order: ascending / descending
dialog_field["sort_order"] = "ascending"

# data_type: string / integer
dialog_field["data_type"] = "string"

# required: true / false
dialog_field["required"] = "true"

dialog_field["values"] = config_list
dialog_field["default_value"] = nil

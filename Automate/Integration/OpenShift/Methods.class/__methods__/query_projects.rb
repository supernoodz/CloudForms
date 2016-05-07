require 'rest-client'

ose_host          = $evm.object['ose_host']
ose_port          = $evm.object['ose_port']
token             = $evm.object.decrypt('ose_pwd')

url = "https://#{ose_host}:#{ose_port}"

query = '/oapi/v1/projects'
$evm.log(:info, query)
rest_return = RestClient::Request.execute(
  method: :get,
  url: url + query,
  :headers => {
    :accept => :json,
    :authorization => "Bearer #{token}"
  },
  verify_ssl: false)
result = JSON.parse(rest_return)

# result['items'].each {|i| p i['metadata']['name'] }

project_list = {}
result['items'].each { |i| project_list[i['metadata']['name']] = i['metadata']['name'] }

project_list[nil] = project_list.empty? ? "<None>" : "<Choose>"

dialog_field = $evm.object

# sort_by: value / description / none
dialog_field["sort_by"] = "description"

# sort_order: ascending / descending
dialog_field["sort_order"] = "ascending"

# data_type: string / integer
dialog_field["data_type"] = "string"

# required: true / false
dialog_field["required"] = "true"

dialog_field["values"] = project_list
dialog_field["default_value"] = nil

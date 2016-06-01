require 'rest-client'

ose_host          = $evm.object['ose_host']
ose_port          = $evm.object['ose_port']
token             = $evm.object.decrypt('ose_pwd')
project           = $evm.root['dialog_project']
deployment_config = $evm.root['dialog_deployment_config']
replicas          = $evm.root['dialog_replicas']

post_params = {
  :kind => "Scale",
  :apiVersion => "extensions/v1beta1",
  :metadata => {
    :name       => deployment_config,
    :namespace  => project
  },
  :spec => {
    :replicas => replicas.to_i
  }
}
$evm.log(:info, post_params)

url   = "https://#{ose_host}:#{ose_port}"
query = "/oapi/v1/namespaces/#{project}/deploymentconfigs/#{deployment_config}/scale"
$evm.log(:info, "#{url}#{query}")

rest_return = RestClient::Request.execute(
  method: :put,
  url: url + query,
  :headers => {
    :accept        => 'application/json',
    :content_type  => 'application/json',
    :authorization => "Bearer #{token}"
  },
  :payload => post_params.to_json,
  verify_ssl: false
)

result = JSON.parse(rest_return)
$evm.log(:info, result)

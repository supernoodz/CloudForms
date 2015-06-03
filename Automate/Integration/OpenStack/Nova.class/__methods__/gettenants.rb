# createInstance.rb
#
# Description: Create intance in OpenStack
#
require 'fog'

def log(level, msg, update_message=false)
  $evm.log(level,"#{msg}")
  $evm.root['service_template_provision_task'].message = msg if $evm.root['service_template_provision_task'] && update_message
end

def get_tenant
  tenant_ems_id = $evm.root['dialog_cloud_tenant']
  log(:info, "Found EMS ID of tenant from dialog: #{tenant_ems_id}")
  return tenant_ems_id if tenant_ems_id.nil?

  tenant = $evm.vmdb(:cloud_tenant).find_by_id(tenant_ems_id)
  log(:info, "Found EMS Object for Tenant from vmdb: #{tenant.inspect}")
  return tenant
end

# basic retry logic
def retry_method(retry_time, msg)
  log(:info, "#{msg} - Waiting #{retry_time} seconds}", true)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

$evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}

openstack   = $evm.vmdb('ems_openstack').first
raise 'OpenStack provider lookup failed' if openstack.nil?

log(:info, "EMS_Openstack: #{openstack.inspect}\n#{openstack.methods.sort.inspect}")

#tenant = get_tenant
#log(:info, "Using tenant: #{tenant.name}")

conn = Fog::Compute.new({
  :provider => 'OpenStack',
  :openstack_api_key => openstack.authentication_password,
  :openstack_username => openstack.authentication_userid,
  :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
#  :openstack_tenant => 'jread-acme-cloudhost'
})

log(:info, "Successfully connected to Nova Service at #{openstack.name}", true)

tenants = conn.tenants.all
log(:info, "Tenants: #{tenants.inspect}")

tenants.each do |t|
  log(:info, "Tenant: #{t.name}") 
end

def log(level, msg)
  $evm.log(level, msg)
end

log(:info, "Begin Automate Method")

#gem 'fog', '>=1.22.0'
require 'fog'

tenant_id = $evm.get_state_var('tenant_id')

# Get the OpenStack EMS from dialog_mid or grab the first one if it isn't set
openstack   = $evm.vmdb('ems_openstack').first
raise 'OpenStack provider lookup failed' if openstack.nil?

log(:info, "Connecting to OpenStack EMS #{openstack[:hostname]}")
conn = nil
# Get a connection as "admin" to Keystone 
conn = Fog::Identity.new({
  :provider => 'OpenStack',
  :openstack_api_key => openstack.authentication_password,
  :openstack_username => openstack.authentication_userid,
  :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
  :openstack_tenant => "admin"
})

tenant_user     = $evm.get_state_var('tenant_user')
tenant_password = $evm.get_state_var('tenant_password')
tenant_email    = $evm.get_state_var('tenant_email')
tenant_name     = $evm.get_state_var('tenant_name')
log(:info, "tenant_user     => #{tenant_user}")
log(:info, "tenant_email    => #{tenant_email}")
log(:info, "tenant_password => #{tenant_password}")
log(:info, "tenant_name     => #{tenant_name}")

user = conn.create_user(tenant_user, tenant_password, tenant_email, tenantId=tenant_id, enabled=true)
log(:info, "Successfully created user #{user.inspect}")

# Store stuff 
$evm.set_state_var('openstack_url', "http://#{openstack[:hostname]}/dashboard/auth/login/")

openstack.refresh

log(:info, "End Automate Method")

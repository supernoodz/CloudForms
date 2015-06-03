# createTenant.rb

def log(level, msg)
  $evm.log(level, msg)
end

def get_role_ids_for_heat(conn)
  roles = []
  conn.list_roles[:body]["roles"].each { |role|
    roles.push(role) if role["name"] == "admin" || role["name"] == "heat_stack_owner" || role["name"] == "_member_"
  }
  return roles
end

log(:info, "Begin Automate Method")

#gem 'fog', '>=1.22.0'
require 'fog'

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

tenant_user = $evm.root['dialog_tenant_user'] #|| $evm.root['user'].name
tenant_email = $evm.root['dialog_tenant_email'] #|| $evm.root['user'].email
tenant_password = $evm.root.decrypt('dialog_tenant_password') #|| rand(36**10).to_s(36)
tenant_name = $evm.root['dialog_tenant_name'] #|| tenant_user + '_' + Time.now.strftime('%Y%m%dT%H%M')

log(:info, "tenant_user     => #{tenant_user}")
log(:info, "tenant_email    => #{tenant_email}")
log(:info, "tenant_password => #{tenant_password}")
log(:info, "tenant_name     => #{tenant_name}")

description = "#{tenant_user}'s Tenant, created by CloudForms Automate"

# Create the new tenant
tenant = conn.create_tenant({
  :description => description,
  :enabled => true,
  :name => tenant_name
})[:body]["tenant"]
log(:info, "Successfully created tenant #{tenant.inspect}")

# Get my keystone user information
myuser = conn.list_users[:body]["users"].select { |user| user["name"] == "#{openstack.authentication_userid}" }.first
log(:info, "Got my user information: #{myuser.inspect}")

# In IceHouse, the user must be a member of the right roles for Heat to work,
# get those role ids, then assign them to the user in the new tenant
myroles = get_role_ids_for_heat(conn)
log(:info, "Got Role IDs for Heat: #{myroles.inspect}")
myroles.each { |role|
  conn.create_user_role(tenant["id"], myuser["id"], role["id"])
}
log(:info, "User Roles Applied: #{conn.list_roles_for_user_on_tenant(tenant["id"], myuser["id"]).inspect}")

# Store Tenant Id 
$evm.set_state_var('tenant_id', tenant["id"])
$evm.set_state_var('tenant_user', tenant_user)
$evm.set_state_var('tenant_email', tenant_email)
$evm.set_state_var('tenant_password', tenant_password)
$evm.set_state_var('tenant_name', tenant_name)

# Initiate a Refresh of the EMS
openstack.refresh

log(:info, "End Automate Method")

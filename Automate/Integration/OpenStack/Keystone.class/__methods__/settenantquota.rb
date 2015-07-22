# setTenantQuota.rb

def log(level, msg)
  $evm.log(level, msg)
end

log(:info, "Begin Automate Method")

require 'fog'

# Get the OpenStack EMS from dialog_mid or grab the first one if it isn't set
openstack   = $evm.vmdb('ems_openstack').first
raise 'OpenStack provider lookup failed' if openstack.nil?

log(:info, "Connecting to OpenStack EMS #{openstack[:hostname]}")

tenant_id = $evm.get_state_var('tenant_id')

# Network Quota

log(:info, "Setting Network Quota")

conn = Fog::Network.new({
  :provider => 'OpenStack',
  :openstack_api_key => openstack.authentication_password,
  :openstack_username => openstack.authentication_userid,
  :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
  :openstack_tenant => "admin"
})

# Network quota_set
# "quota" => {
#   "subnet" => 10,
#   "network" => 10,
#   "floatingip" => 50,
#   "security_group_rule" => 100,
#   "security_group" => 10,
#   "router" => 10,
#   "port" => 50
# }

options = {
 :floatingip => $evm.root['dialog_floating_ips']
}

log(:info, conn.get_quota(tenant_id).inspect)
conn.update_quota(tenant_id, options)
log(:info, conn.get_quota(tenant_id).inspect)

# Compute Quota

log(:info, "Setting Compute Quota")

conn = Fog::Compute.new({
  :provider => 'OpenStack',
  :openstack_api_key => openstack.authentication_password,
  :openstack_username => openstack.authentication_userid,
  :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
  :openstack_tenant => "admin"
})

# Compute quota_set
# "quota_set" => {
#  "injected_file_content_bytes"=>10240,
#  "metadata_items"=>128,
#  "server_group_members"=>10,
#  "server_groups"=>10,
#  "ram"=>51200,
#  "floating_ips"=>10,
#  "key_pairs"=>100,
#  "id"=>"1bdac2b495c5411b8d36967214d0ef73",
#  "instances"=>10,
#  "security_group_rules"=>20,
#  "injected_files"=>5,
#  "cores"=>20,
#  "fixed_ips"=>-1,
#  "injected_file_path_bytes"=>255,
#  "security_groups"=>10
# }

options = {
 :ram => $evm.root['dialog_ram'],
 :instances => $evm.root['dialog_instances'],
 :cores => $evm.root['dialog_cores'],
 # :floating_ips => $evm.root['dialog_floating_ips']
}

log(:info, conn.get_quota(tenant_id).inspect)
conn.update_quota(tenant_id, options)
log(:info, conn.get_quota(tenant_id).inspect)

# Storage Quota

log(:info, "Setting Storage Quota")

conn = Fog::Volume.new({
  :provider => 'OpenStack',
  :openstack_api_key => openstack.authentication_password,
  :openstack_username => openstack.authentication_userid,
  :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
  :openstack_tenant => "admin"
})

# Volume quota_set
# "quota_set" => {
#  "gigabytes"=>1000,
#  "backup_gigabytes"=>1000,
#  "snapshots"=>10,
#  "volumes"=>10,
#  "backups"=>10,
#  "id"=>"1bdac2b495c5411b8d36967214d0ef73"
# }

options = {
  :gigabytes => $evm.root['dialog_volume_gb']
}

log(:info, conn.get_quota(tenant_id).inspect)
conn.update_quota(tenant_id, options)
log(:info, conn.get_quota(tenant_id).inspect)

log(:info, "End Automate Method")

# restartInstances.rb
#
# Description: Restart instances from failed host
#
require 'fog'

#$evm.root.attributes.sort.each { |k, v| $evm.log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}

# Failed host
hypervisor_hostname = $evm.root['dialog_hypervisor_hostname']
$evm.log(:info, "hypervisor_hostname: #{hypervisor_hostname}")

openstack   = $evm.vmdb('ems_openstack').first
raise 'OpenStack provider lookup failed' if openstack.nil?

# Get all the tenants
conn = Fog::Compute.new({
  :provider => 'OpenStack',
  :openstack_api_key => openstack.authentication_password,
  :openstack_username => openstack.authentication_userid,
  :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
  :openstack_tenant => "admin"
})

tenants = conn.tenants.all
$evm.log(:info, "Tenants: #{tenants.inspect}")

# Connect to each tenant and find instances that were running on the failed host
hosted_instances = []
tenants.each do |t|
  $evm.log(:info, "Tenant: #{t.name}")

  conn = Fog::Compute.new({
    :provider => 'OpenStack',
    :openstack_api_key => openstack.authentication_password,
    :openstack_username => openstack.authentication_userid,
    :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
    :openstack_tenant => t.name
  })

  #instances = conn.servers.all(:os_ext_srv_attr_hypervisor_hostname => hypervisor_hostname)
  instances = conn.servers.all
  $evm.log(:info, "Instances: #{instances.inspect}")

  instances.each do |i|
    if i.os_ext_srv_attr_hypervisor_hostname == hypervisor_hostname
      $evm.log(:info, "#{i.name} | #{i.os_ext_srv_attr_instance_name} | #{i.id}")
      hosted_instances << i.id
    end
  end
end

$evm.log(:info, "Hosted Instances: #{hosted_instances.inspect}")

# Re-connect as Admin and start all the instances
conn = Fog::Compute.new({
  :provider => 'OpenStack',
  :openstack_api_key => openstack.authentication_password,
  :openstack_username => openstack.authentication_userid,
  :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
  :openstack_tenant => "admin"
})

body = {
  'os-migrateLive' => {
#    'host' => 'tsp012.osp.belbone.be',
    'block_migration' => false,
    'disk_over_commit' => false,
  }
}

hosted_instances.each do |h|
  $evm.log(:info, "Live Migrating: #{h}") 
  conn.server_action(h, body)
end

sleep(1.minutes)

openstack.refresh

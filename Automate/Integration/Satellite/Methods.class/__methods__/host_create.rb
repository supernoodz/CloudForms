#
# Description: Create configured host record in Foreman
#

begin

	# Method for logging
	def log(level, message)
		@method = '----- foreman host create -----'
		$evm.log(level, "#{@method} - #{message}")
	end

	10.times { log(:info, 'CloudForms Automate Method Started') }

	@debug = true

	require 'rest-client'
	require 'json'
	require 'openssl'
	require 'base64'

  	satellite_host		= $evm.object['satellite_host']
  	satellite_user 		= $evm.object['satellite_user']
  	satellite_password	= $evm.object.decrypt('satellite_password')
  	hostgroup_name 		= $evm.object['hostgroup_name']
  	category_name = 'db_slots'

    case $evm.root['vmdb_object_type']
	when 'miq_provision'
		prov = $evm.root['miq_provision']
		vm = prov.vm unless prov.nil?
	when 'vm'
		vm = $evm.root['vm']
	else
		raise "Unexpected $evm.root['vmdb_object_type']:<#{$evm.root['vmdb_object_type']}>"
	end
	raise 'VM object is empty' if vm.nil?

	#############################
	# Create the host via Foreman
	#############################

	uri_base = "https://#{satellite_host}/api/v2"
	uri = "#{uri_base}"

	headers = {
		:content_type => 'application/json',
		:accept => 'application/json;version=2',
		:authorization => "Basic #{Base64.strict_encode64("#{satellite_user}:#{satellite_password}")}"
	}

	# FIrstly get the hostgroup id using the supplied name

	log(:info, 'Getting hostgroup id from Puppet')

	uri = "#{uri_base}/hostgroups/#{hostgroup_name}"
	log(:info, "uri => #{uri}")

	request = RestClient::Request.new(
		method: :get,
		url: uri,
		headers: headers,
		verify_ssl: OpenSSL::SSL::VERIFY_NONE
	)

	rest_result = request.execute
	log(:info, "return code => <#{rest_result.code}>")
	json_parse = JSON.parse(rest_result)
	log(:info, "json_parse => #{json_parse}") if @debug
	hostgroup_id = json_parse['id'].to_s
	log(:info, "hostgroup_id => <#{hostgroup_id}>")

 	# Now create the host in Puppet via Foreman

  	log(:info, 'Creating host in Puppet')

	hostinfo = {
		:name => vm.name,
		:mac => vm.mac_addresses[0],
		:hostgroup_id => hostgroup_id,
	    :build => 'true'
	}
	log(:info, "hostinfo => #{hostinfo}")

	uri = "#{uri_base}/hosts"
	log(:info, "uri => #{uri}")

    request = RestClient::Request.new(
		method: :post,
		url: uri,
		headers: headers,
		verify_ssl: OpenSSL::SSL::VERIFY_NONE,
		payload: { host: hostinfo }.to_json
	)

	rest_result = request.execute
	log(:info, "return code => <#{rest_result.code}>")

	#############################
	# Query via MAC to determine host id
	#############################

	log(:info, 'Getting host id from Puppet')

	uri = "#{uri_base}/hosts?search=mac=#{vm.mac_addresses[0]}"
	log(:info, "uri => #{uri}")

	request = RestClient::Request.new(
		method: :get,
		url: uri,
		headers: headers,
		verify_ssl: OpenSSL::SSL::VERIFY_NONE
	)

	rest_result = request.execute
	log(:info, "return code => <#{rest_result.code}>")
	json_parse = JSON.parse(rest_result)
	log(:info, "json_parse => #{json_parse}") if @debug
	result = json_parse['results'][0]
	log(:info, "result => <#{result}>") if @debug
	host_id = (result['id']).to_s
	log(:info, "host_id => <#{host_id}>")

	#############################
	# Set the host parameters to allow Puppet to install the required instances
	#############################

	log(:info, 'Setting parameters')
	uri = "#{uri_base}/hosts/#{host_id}/parameters"
	log(:info, "uri => #{uri}")

	# Interate requested database instances 1-4 from dialogue
	for s in 1..4 do
		log(:info, "Iteration => #{s}")
		unless ($evm.root["dialog_instance#{s}_name"]).nil?
			if not ($evm.root["dialog_instance#{s}_name"]).blank?
				parameters_hash = {
					"instance#{s}_name" 	=> $evm.root["dialog_instance#{s}_name"],
					"instance#{s}_port" 	=> $evm.root["dialog_instance#{s}_port"],
					"instance#{s}_password" => $evm.root.decrypt("dialog_instance#{s}_password")
				}

				parameters_hash.each do |k, v|
					log(:info, "#{k} => #{v}") if @debug
					request = RestClient::Request.new(
						method: :post,
						url: uri,
						headers: headers,
						verify_ssl: OpenSSL::SSL::VERIFY_NONE,
			          	payload: {:name => k, :value => v}.to_json
					)

					rest_result = request.execute
					log(:info, "return code => <#{rest_result.code}>")
				end

				# Tag with instances
				tag = s.to_s + '_' + ($evm.root["dialog_instance#{s}_name"]).downcase + '_' + $evm.root["dialog_instance#{s}_port"]
				log(:info, "tag => #{tag}")

				unless $evm.execute('tag_exists?', category_name, tag)
					log(:info, "#{@method} - Creating <#{category_name}/#{tag}> tag")
					$evm.execute('tag_create', category_name, :name => tag, :description => tag)
				end

				vm.tag_assign("#{category_name}/#{tag}")
			end
		end
	end

	log(:info, 'Restarting VM to PXE with new host record')
	# vm.stop
	# sleep(3)
	# vm.start

	10.times { log(:info, 'CloudForms Automate Method Ended') }
	exit MIQ_OK

rescue => err
	log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
	exit MIQ_ABORT

end

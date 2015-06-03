#
# Description: This method sends an e-mail when the following event is raised:
# Events: vm_provisioned
#
# Model Notes:
# 1. to_email_address - used to specify an email address in the case where the
#    vm's owner does not have an  email address. To specify more than one email
#    address separate email address with commas. (I.e. admin@company.com,user@company.com)
# 2. from_email_address - used to specify an email address in the event the
#    requester replies to the email
# 3. signature - used to stamp the email with a custom signature
#

# service_template_provision_task = $evm.root['service_template_provision_task']
# miq_request = service_template_provision_task.miq_request
# requester = miq_request.requester

tenant_user = $evm.get_state_var('tenant_user')
tenant_password = $evm.get_state_var('tenant_password')
tenant_email = $evm.get_state_var('tenant_email')
tenant_name = $evm.get_state_var('tenant_name')
tenant_url = $evm.get_state_var('openstack_url')

$evm.log(:info, "tenant_user     => #{tenant_user}")
$evm.log(:info, "tenant_email    => #{tenant_email}")
$evm.log(:info, "tenant_password => #{tenant_password}")
$evm.log(:info, "tenant_name     => #{tenant_name}")

to = tenant_email

# Get from_email_address from model unless specified below
from = nil
from ||= $evm.object['from_email_address']

# Get signature from model unless specified below
signature = nil
signature ||= $evm.object['signature']

subject = "Your OpenStack Tenant and User request has failed"

body = "Hello #{tenant_user},"

# Email body
body += "<br><br>Your request to provision a new OpenStack Tenant and User failed on #{Time.now.strftime('%A, %B %d, %Y at %I:%M%p')}. "
body += "<br><br>Thank you,"
body += "<br> #{signature}"

$evm.log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}>")
$evm.execute('send_email', to, from, subject, body)

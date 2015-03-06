# Method for logging
def log(level, message)
  @method = '----- Populate Dynamic Dropdown List -----'
  $evm.log(level, "#{@method} - #{message}")
end

def check_status(obj, meth)
  if obj.respond_to?(meth.to_sym)
    if obj.send(meth.to_sym) == true
      log(:info, "Removing #{meth} <#{obj.name}>") if @debug
      return true
    end
  end
  false
end

# @debug = true
vmdb_object = $evm.object['vmdb_object']
object = $evm.vmdb(vmdb_object).all
log(:info, "#{vmdb_object} count => <#{object.count}>") if @debug

values = ['<Choose>'.reverse] # Drop down list bug, reversing output
object.each do | o |
  log(:info, "Processing => <#{o.name}>") if @debug
  log(:info, "        Id => <#{o.id}>") if @debug

  # Filter out selected values
  next if check_status(o,'orphaned')
  next if check_status(o,'archived')
  next if check_status(o,'retired')

  values << o.name.reverse # Drop down list bug, reversing output
end

values = values.sort.uniq
log(:info, "Item count => #{values.count}")

# Populate the dialogue
dialog_field                  = $evm.object
dialog_field['sort_order']    = 'ascending'
dialog_field['data_type']     = 'array'
dialog_field['required']      = 'true'
dialog_field['default_value'] = '<Choose>'
dialog_field['values']        = values

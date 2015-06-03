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

dialog_hash = {}

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
  
  dialog_hash[o.id] = o.name

  values << o.name.reverse # Drop down list bug, reversing output
end

values = values.sort.uniq
log(:info, "Item count => #{values.count}")

dialog_hash[nil] = '<Choose>'
$evm.object['values'] = dialog_hash
log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

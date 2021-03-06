class Iblox

#config find
def self.config_find()
  config_search_paths=['~/.iblox.yaml','/etc/iblox.yaml']
  config_search_paths.each do |path|
  #If #{path} is a file and re can read it, return it.
    if File.exists?(File.expand_path(path))
      return (path)
    end
  end
  #no config found
  raise ("No config found!")
end

#Open infoblox connection object
def self.connect (username, password, host, wapi_version)
  ::Infoblox.wapi_version = "#{wapi_version}"
  connection = Infoblox::Connection.new(username: "#{username}",password: "#{password}", host: "#{host}")
  return connection
end

def self.batch_dns_load(batch_file)
  #First, see if we're using .csv, .yaml/.yml, or .json
  ext=batch_file.split('.')[-1]
  if ext.match(/(csv|yaml|yml|json)/)
    #make sure it exists
    if (File.exist? File.expand_path batch_file)
      batch_data=[]
      case ext
      when "csv"
        batch_data=[]
        f=File.open(batch_file)
        f.each_line do|line|
          entry = {}
          entry[:fqdn] = line.split(',')[0].chomp
          entry[:ip] = line.split(',')[1].chomp
          batch_data.push(entry)
        end
      when "yaml","yml"
        batch_data=YAML::load(File.open(batch_file))
      when "json"
        batch_data=JSON.parse(File.read(batch_file),{:symbolize_names => true})
      else
        raise ("Batch filetype #{ext} not supported")
      end
      return batch_data
    else
      raise "Batch file does not exist"
    end
  else
    raise ("Batch filetype #{ext} not supported")
  end
end
def self.batch_dhcp_load(batch_file)
  ext=batch_file.split('.')[-1]
  if ext.match(/(csv|yaml|yml|json)/)
    #make sure it exists
    if (File.exist? File.expand_path batch_file)
      batch_data=[]
      case ext
      when "csv"
        batch_data=[]
        f=File.open(batch_file)
        f.each_line do|line|
          entry = {}
          entry[:fqdn] = line.split(',')[0].chomp
          #figure out if this entry is an ip or CIDR
          if line.split(',')[1].chomp.match('/')
            #puts "CIDR"
            entry[:network] = line.split(',')[1].chomp
          else
            #puts "IP"
            entry[:ip] = line.split(',')[1].chomp
          end
          entry[:mac] = line.split(',')[2].chomp
          batch_data.push(entry)
        end
      when "yaml","yml"
        batch_data=YAML::load(File.open(batch_file))
      when "json"
        batch_data=JSON.parse(File.read(batch_file),{:symbolize_names => true})
      else
        raise ("Batch filetype #{ext} not supported")
      end
      return batch_data
    else
      raise "Batch file does not exist"
    end
  else
    raise ("Batch filetype #{ext} not supported")
  end
end
#Check we got an IPv4 address
def self.ipv4check (ip)
  ipaddr1 = IPAddr.new "#{ip}"
  if ipaddr1.ipv4?
    return true
  else
    raise "#{ip} is not a valid IP address!"
    return false
  end
end

#check that the ip we got is in the network we got
def self.ipv4netcheck(ip, network)
  net=IPAddr.new "#{network}"
  if net.include?(IPAddr.new "#{ip}")
    return true
  else
    raise "#{ip} is not within #{network}"
    return false
  end
end

#Check if the record we want exists
def self.dns_exists(fqdn,ip,verbose,connection)
  #try to find A
  a_record = Infoblox::Arecord.find( connection, { name: fqdn, ipv4addr: ip }).first
  #try to find PTR
  ptr_record = Infoblox::Ptr.find( connection, { ptrdname: fqdn, ipv4addr: ip}).first
  if a_record == nil or ptr_record == nil
    return false
  else
    return true
  end
end
#Add dns A record + PTR record
def self.dns_add(fqdn,ip,verbose,connection)
  if verbose == true
    puts "Adding DNS A Record for #{fqdn}(#{ip})"
  end
  a_record = Infoblox::Arecord.new(connection: connection, name: fqdn, ipv4addr: ip)
  ptr_record = Infoblox::Ptr.new(connection: connection, ptrdname: fqdn, ipv4addr: ip)
  a_record.post
  ptr_record.post
end
#Update dns record
def self.dns_update(fqdn,ip,new_fqdn,new_ip,verbose,connection)
  a_record = Infoblox::Arecord.find( connection, { name: fqdn, ipv4addr: ip }).first
  ptr_record = Infoblox::Ptr.find( connection, { ptrdname: fqdn, ipv4addr: ip}).first
  if a_record == nil or ptr_record == nil
    raise 'no record to update found'
  else
    if new_fqdn != nil
      a_record.name = new_fqdn
      ptr_record.ptrdname = new_fqdn
    end
    if new_ip != nil
      a_record.ipv4addr = new_ip
      ptr_record.ipv4addr = new_ip
    end
    a_record.view=nil
    ptr_record.view=nil
    ptr_record.ipv6addr=nil
    a_record.put
    ptr_record.put
  end
end
#Delete DNS record
def self.dns_delete(fqdn,ip,verbose,connection)
  if verbose == true
    puts "Deleting DNS A Record for #{fqdn}(#{ip})"
  end
  a_record = Infoblox::Arecord.find( connection, { name: fqdn, ipv4addr: ip }).first
  ptr_record = Infoblox::Ptr.find( connection, { ptrdname: fqdn, ipv4addr: ip}).first
  #pp a_record
  #pp ptr_record
  a_record.delete
  ptr_record.delete
end


#check for DHCP reservation by mac
def self.dhcp_exists(mac,verbose,connection)
  dhcp_res = Infoblox::Fixedaddress.find( connection, { mac: mac}).first
  if dhcp_res == nil
    return false
  else
    return true
  end
end
def self.dhcp_next(network,verbose,connection,range)
  if verbose == true
    puts "Getting next available IP address for network #{network}"
  end
  if range == true
    range = Infoblox::Range.find(connection, network: network).first
    ip = range.next_available_ip[0]
  else
    net = Infoblox::Network.find(connection, network: network).first
    ip = net.next_available_ip[0]
  end
  return ip
end
def self.dhcp_add(fqdn,ip,mac,verbose,connection)
  if verbose == true
    puts "Adding DHCP fixed address for #{fqdn}(#{ip}  #{mac})"
  end
  dhcp_res = Infoblox::Fixedaddress.new(connection: connection,
  name: fqdn,
  mac: mac,
  ipv4addr: ip,
  )
  dhcp_res.post
end
def self.dhcp_update(fqdn,ip,mac,new_fqdn,new_ip,new_mac,verbose,connection)
  dhcp_res = Infoblox::Fixedaddress.find( connection, { ipv4addr: ip, mac: mac}).first
  if dhcp_res == nil
    raise 'no record to update found'
  else
    if new_fqdn != nil
      dhcp_res.name = new_fqdn
    end
    if new_ip != nil
      dhcp_res.ipv4addr = new_ip
    end
    if new_mac != nil
      dhcp_res.mac = new_mac
    end
    dhcp_res.post
  end
end
def self.dhcp_delete(fqdn,ip,mac,verbose,connection)
  if verbose == true
    puts "Deleting DHCP fixed address for #{fqdn}(#{ip}  #{mac})"
  end
  dhcp_res = Infoblox::Fixedaddress.find( connection, { ipv4addr: ip, mac: mac}).first
  dhcp_res.delete

end
end

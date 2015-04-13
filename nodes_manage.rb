#Used to create puppet agent dir
require 'erb'
require 'rubygems'
require 'json'

class Firewall_rule
  @description
  @rule_propertys

  attr_accessor:description
  attr_accessor:rule_properties

  def initialize
  end
end




class Agent_setting
  PUPPET_DIR = "/etc/puppet"
  reg_hostname = /[0-9a-z]{32}.cs1cloud.internal/
  @id = nil
  @settings = nil
  @hostname = nil
  @firewall
  
  def initialize(id)
    @id = id
    @settings = Hash.new
    @path = "#{PUPPET_DIR}/manifests/nodes/#{@id}"
    @firewall = Hash.new
    #create empty vm setting dir
    if(!File.exist?("#{@path}"))
     Dir.mkdir("#{@path}")
    end
    rules_file = File.open("#{@path}/extra_fw_rules",File::CREAT||File::READ)  
    rules_file.read.strip.split("firewall").each do  |rule|
      next if rule.empty?
      #extract filewall data from rule string wtih the regular expression
      rule_reg = %r{\A\{'(\d+)([[:alpha:][:digit:][:punct:][:space:]]+)':([\s\S]*)\}}
      
      return  unless((rule_reg =~rule) == 0)  
      rule_id = $1.strip
      @firewall[rule_id] =   Firewall_rule.new
        @firewall[rule_id].description  =  $2.strip
        rule_properties = $3.gsub(/[\s]/,"").split("=>")
        rule_set = Hash.new
        # this each argument try to deal with the special situation like 'aaa=>[bbb,ccc,dddd]'
        rule_properties.each_with_index  do |property,index|
          if(index>0)
            key = index==1?rule_properties[0]:rule_properties[index-1].rpartition(",")[2]
            rule_set[key] = property.rpartition(",")[0]
          end
        end
        @firewall[rule_id].rule_properties  = rule_set
    end
    p @firewall
    configure_init_pp
  end
  
  def configure_init_pp
    #create puppet agent initial settings
    init_erb = ERB.new(File.read("erb/init.erb"))
    File.delete("#{@path}/init.pp") if File.exist?("#{@path}/init.pp")
    init_pp = File.new("#{@path}/init.pp","w")
    init_pp.write(init_erb.result binding)
    init_pp.close
  end

  def get_all_firewall_rules
    string = ("{\"firewall_rules\":[")
    @firewall.each do |key,value|
      string.concat("{\"id\":\"#{key}\",")
      string.concat("\"description\":\"#{value.description}\",")
      string.concat("\"properties\":{")
      value.rule_properties.each do |prop,opts|
      string.concat("\"#{prop}\":\"#{opts}\",")
      end
      string.chop!
      string.concat("}},")
    end
    string.chop!
    string.concat("]}")
    puts  string
  end
  def add_new_port(id,source,port,protocol,description)
    #source address regex rule
    reg_source = /\A[!]?((?:(?:25[0-5]|((2[0-4]\d)|(1\d{2})|(\d\d)|(\d)))\.){3}(?:25[0-5]|((2[0-4]\d)|(1\d{2}))|(\d\d)|(\d))\/(?:(?:3[0-1]|[1-2][\d]|[\d])))\z/
    # reg_port = /\A([6][0-5][0-5][0-3][0-5]|[1-5]\d{4}|[1-9]|[1-9]\d{1,3})\z/
    reg_protocol = ["all","icmp","udp","tcp"]
    
    return "invalid source address" unless (source.empty?||(reg_source =~ source)==0)
    return "invalid protocol" unless  reg_protocol.include?(protocol)
    #    return "invalid hostname" unless  (reg_hostname =~ @hostname) == 0
    
    new_rules =  @firewall.has_key?(id)?@firewall[id]:Firewall_rule.new
    new_rules.description = description
    new_properties = Hash.new
    unless(source.empty?)
      new_properties["source"] = source
    end
    new_properties["port"] = port
    new_properties["action"] = "accept"
    new_properties["proto"] = protocol
    new_rules.rule_properties = new_properties
    @firewall[id] = new_rules
    updateSettings
    return "OK"
  end

  def updateSettings
    
    output = ""
    @firewall.each do |key,value|
      output.concat("firewall{")
      output.concat("\'#{key} #{value.description}\':\n")
      value.rule_properties.each do |prop,opts|
        output.concat("\t#{prop}=>#{opts},\n")
      end
      output.concat("}\n")
    end
    puts output
    File.open("#{@path}/extra_fw_rules","w+") do |file|
          file.puts(output)
    end
  end

  
  def add_app(key,app)
    @settings[key] = app
  end
end

setting = Agent_setting.new("8a8a9e024c7dc717014c7e50b812000f.cs1cloud.internal")
setting.add_new_port("007","10.1.11.0/24","7770","icmp","test for it")
puts setting.get_all_firewall_rules

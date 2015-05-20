#Used to create puppet agent dirx
require 'erb'
require 'rubygems'
require 'json'
require 'fileutils'

class Firewall_rule
  @description
  @rule_propertys

  attr_accessor :description,:rule_properties

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
   #p @firewall
    configure_init_pp
    add_init_to_site
  end

  def remove_puppet_agent
    delete_init_from_site
    remove_dir
    clean_cert
  end
  
  def remove_dir
        FileUtils.rm_rf "#{@path}"
  end

  def clean_cert
    `puppet cert clean #{@id}`
  end
  
  def add_init_to_site
    site = ""
    File.open("#{PUPPET_DIR}/manifests/site.pp","r") do |file|
      site = file.read
    end
    unless(site.include? "#{@id}")
      site.insert site.rindex("}"),"\timport\t\"nodes/#{@id}/init.pp\"\n"
    end
    File.open("#{PUPPET_DIR}/manifests/site.pp","w") do |file|
      file.puts(site)
    end
  end

  def delete_init_from_site
    site =""
    File.open("#{PUPPET_DIR}/manifests/site.pp","r") do |file|
      site = file.read
    end
    site.gsub!( /(\s+import\s+\"nodes\/#{@id}\/init.pp\"\s*)$/,"")
    File.open("#{PUPPET_DIR}/manifests/site.pp","w") do |file|
      file.puts(site)
    end
  end

  def configure_init_pp
    #create puppet agent initial settings
    init_erb = ERB.new(File.read("#{File.dirname(__FILE__)}/erb/init.erb"))
    if File.exist?("#{@path}/init.pp")
      file  = File.open("#{@path}/init.pp","r").read
      init_firewall file[file.index("#start")+6..file.index("#end")-1]
      #      get_all_firewall_rules
      updateSettings
      return
    end
    init_pp = File.new("#{@path}/init.pp","w")
    init_pp.write(init_erb.result binding)
    init_pp.close
  end

  def init_firewall firewalls
    firewalls.strip.split("firewall").each do  |rule|
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
            if(key=="source")
              rule_set[key] = property.rpartition(",")[0].gsub(/\"/,'')
            else
              rule_set[key] = property.rpartition(",")[0]
            end
          end
        end
        @firewall[rule_id].rule_properties  = rule_set
    end   
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

  def delete_port(id)
    @firewall.delete(id)
  end
  
  def add_new_port(id,source,port,protocol,description)
    #source address regex rule
    reg_source = /\A[!]?((?:(?:25[0-5]|((2[0-4]\d)|(1\d{2})|(\d\d)|(\d)))\.){3}(?:25[0-5]|((2[0-4]\d)|(1\d{2}))|(\d\d)|(\d))\/(?:(?:3[0-1]|[1-2][\d]|[\d])))\z/
    # reg_port = /\A([6][0-5][0-5][0-3][0-5]|[1-5]\d{4}|[1-9]|[1-9]\d{1,3})\z/
    reg_protocol = ["all","udp","tcp"]
    
    return "failed!invalid source address" unless (source.empty?||(reg_source =~ source)==0)
    return "failed!invalid protocol" unless  reg_protocol.include?(protocol)
    #    return "invalid hostname" unless  (reg_hostname =~ @hostname) == 0
    
    new_rules =  @firewall.has_key?(id)?@firewall[id]:Firewall_rule.new
    new_rules.description = description
    new_properties = Hash.new
    unless(source.empty?)
      new_properties["source"] = source
    end
    if(protocol!="all")
      new_properties["port"] = port
    else
      new_properties["port"] = nil
    end
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
        if(prop=="source")
          output.concat("\t#{prop}=>\"#{opts}\",\n")
        else
          unless(prop=="port"&&opts==nil)
            output.concat("\t#{prop}=>#{opts},\n")
          end
        end
      end
      output.concat("}\n")
    end
    init_setting = File.open("#{@path}/init.pp","r").read
    #puts init_setting
    init_setting.gsub!(/(#start[\s\S]+#end)/,"#start\n#{output}  #end")
    #puts init_setting
    File.open("#{@path}/init.pp","w+") do |file|
      file.puts(init_setting)
    end
  end

  
  def add_app(key,app)
    @settings[key] = app
  end
end

#setting = Agent_setting.new("8a8a9e024c7dc717014c7e50b812000f.cs1cloud.internal")
#setting.add_new_port("007","10.1.11.0/24","7770","icmp","test for it")
#
#puts setting.get_all_firewall_rules
#Agent_setting.delete_init_from_site
#Agent_setting.clean_cert
#setting = Agent_setting.new("8a8a16c44ce53df3014ce557666f0015.cs1cloud.internal")
#setting.remove_puppet_agent

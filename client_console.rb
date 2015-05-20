require 'rubygems'
require 'net/ssh'
require File.expand_path('../nodes_manage', __FILE__)
require 'ping'


class ClientInitial

  NAME_POSTFIX = '.cs1cloud.internal'
  
  def initialize(vmid,ip,user,password)
    unless (vmid&&ip&&user&&password)
      puts "invalid parameter"
      return
    end
    @vmname = vmid + NAME_POSTFIX
    @ip = ip
    @user = user
    @password = password
    puts "Prepare for puppet agent settings..."
    @agent_settings = Agent_setting.new(@vmname)
    puts "OK!"
    @status = true
  end

  def build
       connect = false
    @times = 15
    puts "Waiting system start..."
    puts "Connect to host:#{@ip}."

    return "false" if(@password.nil?)
    15.times do
      begin
        File.delete("/root/.ssh/known_hosts") if File.exist?("/root/.ssh/known_hosts")
        Net::SSH.start(@ip,@user, :password => @password) do |ssh|
          puts "connect success"
          puts "initial zabbix agent"
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb configzabbix /etc/zabbix 172.16.20.63 -Hostname #{@vmname.split(".")[0]}")
          return "failed!initial zabbix"  if(output.chomp.end_with? "-1")
          ssh.exec!("service zabbix-agent restart")
          puts "OK!"
          begin
            puppet_version = ssh.exec!          "puppet --version"
            return "failed!puppet uninstalled" if  (/[3].[0-6].[0-9]/ =~ puppet_version).nil?
          rescue
            return "failed!puppet uninstalled"
          end
          puts "Start init vm settings..."
          connect = true
=begin
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb yumupdate")
          puts output.chomp
          if  output.chomp.end_with? "-1"
            @status = false
            return "failed! yum update failed"
          end
=end
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb check puppet 10.1.11.189")
          puts output
          if output.chomp.end_with? "-1"
            @status = false
            return "failed! modify puppet master failed"
          end
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb hostname #{@vmname}")
          puts output
          if  output.chomp.end_with? "-1"
            @status = false
            return "failed! failed to modify hostname"
          end
          puts "delete cert"
          puts `puppet cert clean #{@vmname}`
          puts "rm ssl"
          ssh.exec! "rm -rf /var/lib/puppet/ssl)"
          puts "stop iptables"
          puts ssh.exec! "service iptables stop"
          #output = ssh.exec! "ruby /etc/puppet/initial_settings.rb testpuppet"
          #puts "Config puppet:",output
          sleep 10
          puts "OK!Starting puppet..."
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb restartpuppet")
          puts output
          if output.chomp.end_with? "-1"
            @status = false
            return "failed!failed to restart puppet"
          end
          return "success"
        end
      rescue
        if(!connect)
          puts "Connection error(#{$!})!Waiting next time..."
        else
          return "failed!#{$!}"
        end
        sleep 40
        @times -=1
        puts "Reconnect target VM(times: #{15-@times})"
      end
    end
    @status = false if @times == 0
  end

  def destroy
    puts "removing agent settings..."
    @agent_settings.remove_puppet_agent
    "OK!"
  end

  def add_new_firewall(id,source,port,protocol,descrition)
    begin
      if(source=="null")
        puts @agent_settings.add_new_port id,"",port,protocol,descrition
      else
        puts  @agent_settings.add_new_port id,source,port,protocol,descrition
      end
      @agent_settings.updateSettings
     # kick_it
    rescue
      puts "error!#{$!}"
    end
  end

  def get_status
    return @status
  end

  def delete_firewall(id)
    begin
      @agent_settings.delete_port(id)
      @agent_settings.updateSettings
      kick_it
    rescue
      puts "error!#{$!}"
    end
  end

  def get_all_firewall
    @agent_settings.get_all_firewall_rules
  end

  def kick_it
    puts `puppet kick --host #{@ip}`
  end
  
end
#p ARGV
set = Hash.new
set[ARGV[1]] = ClientInitial.new(ARGV[1],ARGV[2],ARGV[3],ARGV[4])
unless(ARGV[0].nil?)
  case ARGV[0]
  when "delete"
    puts set[ARGV[1]].destroy
  when "build"
    message = set[ARGV[1]].build
    if(message=="success")
      puts "OK!"
    else
      puts message
    end
  when "firewall"
    if(ARGV[5]=="add")
      set[ARGV[1]].add_new_firewall(ARGV[6],ARGV[7],ARGV[8],ARGV[9],ARGV[10]);
    else
      if ARGV[5] == "delete"
        set[ARGV[1]].delete_firewall(ARGV[6])
      else
        set[ARGV[1]].get_all_firewall
      end
    end
      
  else
    puts "faied!unkonw command:#{ARGV[0]}"
  end
else
  puts "failed!invalid command"
end

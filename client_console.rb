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
    @times = 10
    puts "Waiting system start..."
    puts "Connect to host:#{@ip}."

    return "false" if(@password.nil?)
    10.times do
      begin
        File.delete("/root/.ssh/know_hosts") if File.exist?("/root/.ssh/know_hosts")
        Net::SSH.start(@ip,@user, :password => @password) do |ssh|
          puts "connect success"
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
          
          ssh.exec! "rm -rf /var/lib/puppet/ssl)"
          ssh.exec! "service iptables stop"
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
        sleep 30
        @times -=1
        puts "Reconnect target VM(times: #{10-@times})"
      end
    end
    @status = false if @times == 0
  end

  def destroy
    puts "removing agent settings..."
    @agent_settings.remove_puppet_agent
    "OK!"
  end

  def get_status
    return @status
  end
end
#p ARGV
client = ClientInitial.new(ARGV[1],ARGV[2],ARGV[3],ARGV[4])
unless(ARGV[0].nil?)
  case ARGV[0]
  when "delete"
    puts client.destroy
  when "build"
    message = client.build
    if(message=="success")
      puts "OK!"
    else
      puts message
    end
  else
    puts "faied!unkonw command:#{ARGV[0]}"
  end
else
  puts "failed!invalid command"
end

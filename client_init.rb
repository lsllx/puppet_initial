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
    puts "Prepare for puppet agent settings..."
    @agentSettings = Agent_setting.new(@vmname)
    puts "OK!"
    @status = true
    connect = false
    @times = 10
    puts "Waiting system start..."
    puts "Connect to host:#{ip}."
    sleep 30
    10.times do
      begin
        Net::SSH.start(ip,user, :password => password) do |ssh|
          puts "connect success"
          puts "Start init vm settings..."
          connect = true
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb yumupdate")
          puts output.chomp
          if  output.chomp.end_with? "-1"
            @status = false
            return
          end
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb check puppet 10.1.11.189")
          puts output
          if output.chomp.end_with? "-1"
            @status = false
            return
          end
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb hostname #{@vmname}")
          puts output
          if  output.chomp.end_with? "-1"
            @status = false
            return
          end
          
          ssh.exec! "rm -rf /var/lib/puppet/ssl)"
          output = ssh.exec! "ruby /etc/puppet/initial_settings.rb testpupppet"
          puts output
          sleep 10
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb restartpuppet")
          puts output
          if output.chomp.end_with? "-1"
            @status = false
            return
          end
          puts "success"
          return
        end
      rescue
        if(!connect)
          puts "Connection error(timeout)!Waiting next time..."
        else
          puts $!
          return
        end
        sleep 30
        @times -=1
        puts "Reconnect target VM(times: #{10-@times})"
      end
    end
    @status = false if @times == 0
  end

  def get_status
    return @status
  end
end
#
client = ClientInitial.new(ARGV[0],ARGV[1],ARGV[2],ARGV[3])
puts client.get_status

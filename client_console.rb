#详细解释下这个脚本文件的作用外加ruby的基本规则
#ruby是一门动态的脚本语言，为了方便你们了解我会在doc文件夹中给出我看过的ruby书籍，自己花时间了解就可以了，我也会写的比较详细

#这儿的require其实就和java中的import有点类似，不需要多解释
#第三个require中的用法比较特殊，__FILE__是特指当前脚本的文件位置，这整句话的意思就是说引用当前文件下的nodes_manage文件
require 'rubygems'
require 'net/ssh'
require File.expand_path('../nodes_manage', __FILE__)
require 'ping'

#这个class的主要作用有三个：
#build：初始化一个puppet agent到目标机器上去
#delete：删除一个puppet agent
#firewall：防火墙规则的管理
#每个模块我都会尽量详细的解释
class ClientInitial
#这个是一个静态变量，表示每台机器的hostname的后缀
  NAME_POSTFIX = '.cs1cloud.internal'
  #在ruby中 initialize代表的是创建一个对象时如何去初始化，类比java的构造器
  #在这里我使用了四个参数作为初始化，第一个是指scloud系统中的vmId，其余的不用多解释
  def initialize(vmid,ip,user,password)
    unless (vmid&&ip&&user&&password)
      puts "invalid parameter"
      return
    end
    #这里的vmname是vmId加前缀组成的
    @vmname = vmid + NAME_POSTFIX
    @ip = ip
    @user = user
    @password = password
    puts "Prepare for puppet agent settings..."
    #这里会new一个Agent_setting对象，这个对象的作用是获取一个机器在puppet-master端的puppet配置文件
    #详细的解释可以去node_manage.rb中查看
    @agent_settings = Agent_setting.new(@vmname)
    puts "OK!"
    @status = true
  end

  #这个是ruby的一个方法，类似与java的方法
  #这个方法的作用是初始化一个新的puppet-agent
  def build
       connect = false
    #重复尝试次数
    @times = 15
    puts "Waiting system start..."
    puts "Connect to host:#{@ip}."

    return "false" if(@password.nil?)
    15.times do
      begin
       #删除本地之前的SSH已知主机记录，防止以前登录的某个IP在被重新分配之后无法连接
       #这里的if使用方式是如果IF的后面的条件满足，则执行前面的语句，在ruby中是常见的写法
        File.delete("/root/.ssh/known_hosts") if File.exist?("/root/.ssh/known_hosts")
        #这里使用了ruby的Net库中的SSH类的start方法来连接到远程主机中
        #在ruby中 do end就类似与Java中的大括号，表示一个语句块，比如if（）｛。。。｝ 在ruby中一般都是if（）do 。。。 end
        #而在后面的|ssh|则是ruby的一种常见的写法，一般来说，下面这段话等同与
        # ssh =  Net::SSH.start(@ip,@user, :password => @password)
        # ssh的用法有很多 有兴趣可以直接去百度查
        # 这里我主要用到的是ssh的exec方法
        # 这个方法会在目标主机执行后面字符串中的语句，然后返回一个执行结果的字符串
        Net::SSH.start(@ip,@user, :password => @password) do |ssh|
          puts "connect success"
          puts "initial zabbix agent"
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb configzabbix /etc/zabbix 172.16.20.63 -Hostname #{@vmname.split(".")[0]}")
          return "failed!initial zabbix"  if(output.chomp.end_with? "-1")
          ssh.exec!("service zabbix-agent restart")
          puts "OK!"
          #这里的begin rescue end 其实就是java中的try catch，为了验证客户端的puppet版本是低于3.6.0且高于3.0.0的
          begin
            puppet_version = ssh.exec!          "puppet --version"
            return "failed!puppet uninstalled" if  (/[3].[0-6].[0-9]/ =~ puppet_version).nil?
          rescue
            return "failed!puppet uninstalled"
          end
          puts "Start init vm settings..."
          connect = true
          #这部分原来是为机器做yum更新的 由于 更新速度过慢 现在已经舍弃
=begin
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb yumupdate")
          puts output.chomp
          if  output.chomp.end_with? "-1"
            @status = false
            return "failed! yum update failed"
          end
=end
          #这部分主要是为了检查目标机器的puppet-master的域名有没有对应的解析地址
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb check puppet 10.1.11.189")
          puts output
          if output.chomp.end_with? "-1"
            @status = false
            return "failed! modify puppet master failed"
          end
          #这部分是为了修个目标主机的本机hostname
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb hostname #{@vmname}")
          puts output
          if  output.chomp.end_with? "-1"
            @status = false
            return "failed! failed to modify hostname"
          end
          puts "delete cert"
          #这部分清除之前可能会存在的同样名称的虚拟机证书
          puts `puppet cert clean #{@vmname}`
          puts "rm ssl"
          #这部分删除目标主机中的证书文件，puppetagent在启动后会自动生成新的
          ssh.exec! "rm -rf /var/lib/puppet/ssl)"
          puts "stop iptables"
          #这部分是停止了iptables，让puppet可以正确的从puppet-master获取证书
          puts ssh.exec! "service iptables stop"
          #output = ssh.exec! "ruby /etc/puppet/initial_settings.rb testpuppet"
          #puts "Config puppet:",output
          #等待10秒
          sleep 10
          puts "OK!Starting puppet..."
          #重启puppet（若未启动则启动 若启动了则重启）
          output = ssh.exec!("ruby /etc/puppet/initial_settings.rb restartpuppet")
          puts output
          if output.chomp.end_with? "-1"
            @status = false
            return "failed!failed to restart puppet"
          end
          #返回成功信息
          return "success"
        end
      rescue
        #如果未成功则重试，持续15次，间隔40s
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

 #删除puppet的残留信息
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
  #删除防火墙规则，并且更新目标主机
  def delete_firewall(id)
    begin
      @agent_settings.delete_port(id)
      @agent_settings.updateSettings
      kick_it
    rescue
      puts "error!#{$!}"
    end
  end
#获取所有的防火墙规则，这里我会生成一个json的返回值
  def get_all_firewall
    @agent_settings.get_all_firewall_rules
  end
 #更新目标主机的puppet配置
  def kick_it
    puts `puppet kick --host #{@ip}`
  end
  
end
#p ARGV

#上面的东西是一个类的整体构造
#这里开始的所有命令 会在调用这个脚本文件时候执行
#这里的之所以要用set，是为了避免两个创建虚机命令同时发送过来时导致错误，
#这里的Hash类比与Java的Map
#通过vmID不同保证整个运行过程中不会出现冲突
#这里的ARGV和Java中main中接收到的args是一样的，即命令列表
#具体的命令做了什么 对应起来很容易看懂的
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

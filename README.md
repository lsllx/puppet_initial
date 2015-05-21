#**这个文件主要为了说明每个脚本的作用，方便大家去熟悉**
 >client_console.rb主要接收来自于Scloud的命令，命令的格式如下：
 >`ruby client_console.rb option id targetip username password suboption [args] ` 
 >具体的使用方式可以参考我在scloud中写的执行类（VMManager/type包中）

  >nodes_manage.rb主要是主要是对每台虚机的puppet配置文件进行管理的，包括初始的引用包，防火墙规则的读取新增和修改，以后可能还会添加应用配置规则相关的东西。初始化的模版在erb文件夹下
  
  >client_script文件夹下的initial_settings.rd是放在虚拟机模版中的文件(在这里我固定的放在了/etc/puppet/下)
  
  >它主要是用来作为执行包括修改hostname，puppetmaster的dns，启动停止重启puppet agent等功能的，为了满足重启后保证puppet
  agent仍然启动的条件，我们还需要在crontab中添加一条规则：
  
  >`*/3 * * * * root ruby /etc/puppet/initial_settings.rb startpuppet >/dev/null 2>&1`
  
  >这条规则主要是3分钟检查一次puppet agent有没有启动，直接编辑/etc/crontab加入规则即可
  
  >config文件夹下面的三个配置文件都放在（/etc/puppet/）下，它们的的作用：
  
  >（master）puppet.conf puppet-master配置文件
  
  > auth.conf		puppet-agent 配置文件，主要放行了puppet-master的run请求
  
  >puppet.conf 		puppet-agent 配置文件，增加了监听puppet-master的kick请求
  
  

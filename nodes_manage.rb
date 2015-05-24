#Used to create puppet agent dirx
require 'erb'
require 'rubygems'
require 'json'
require 'fileutils'

#这里定义的是防火墙的规则类
#@开头的就是java中的变量，这里的变量是private的
#若要在外部访问，则需在attr_accessor中指定
class Firewall_rule
  @description
  @rule_propertys

  attr_accessor :description,:rule_properties

  def initialize
  end
end



#这部分是puppet-agent在puppet-master中的配置管理
class Agent_setting
  #使用到的变量和常量
  #puppet的安装地址
  PUPPET_DIR = "/etc/puppet"
  #puppet-agent的hostname的正则校验规则
  reg_hostname = /[0-9a-z]{32}.cs1cloud.internal/
  #id就是puppet-agent的hostname
  @id = nil
  #puppetagent的设置（现在暂时没有）
  @settings = nil
  #基本没有用到 可以忽略
  @hostname = nil
  #puppet-agent的防火墙规则
  @firewall
  
  #初始化
  def initialize(id)
    @id = id
    @settings = Hash.new
    #指定puppet的配置文件路径
    @path = "#{PUPPET_DIR}/manifests/nodes/#{@id}"
    #为puppet-agent的防火墙规则创建空列表
    @firewall = Hash.new
    #create empty vm setting dir
    #如果判断有没有该配置的文件夹，没有则新建
    if(!File.exist?("#{@path}"))
     Dir.mkdir("#{@path}")
    end
   #p @firewall
   #初始化配置文件
    configure_init_pp
  #将配置文件加入到puppet管理文件中
    add_init_to_site
  end

 #删除puppet-agent的配置残留项
  def remove_puppet_agent
    #从puppet-master的管理文件中删除配置节点
    delete_init_from_site
    #删除对应的配置文件夹
    remove_dir
    #清理puppet-master保存的证书文件
    clean_cert
  end
  #这两个不用多说，应该都懂
  def remove_dir
        FileUtils.rm_rf "#{@path}"
  end

  def clean_cert
    `puppet cert clean #{@id}`
  end
  #这个主要是为了从puppet-master的主配置文件中清除不用的puppet-agent信息
  def add_init_to_site
    site = ""
    #这里的方法主要是读取site.pp中的所有文件，当然在这里其实有点欠考虑，在高并发下可能出现的数据不一致问题
    #如果这里有这个问题的话，可以采取这样的修改方式，即在打开该文件前，在文件夹中新建一个site.lock文件，完成后删除
    #然后在打开这个文件前先扫描有没有lock文件，有就等待一定时间然后再打开
    File.open("#{PUPPET_DIR}/manifests/site.pp","r") do |file|
      site = file.read
    end
    #unless就是if反过来的用法 if（a==0） 等于unless（a!=0）
    unless(site.include? "#{@id}")
      #rindex的意思是茶盅整个String中的最后一个匹配字符串出现的地方
      #insert就是插入的意思
      #在这里来看这个unless语句就是添加一个import nodes 到文件最后
      site.insert site.rindex("}"),"\timport\t\"nodes/#{@id}/init.pp\"\n"
    end
    #写入新的文件
    File.open("#{PUPPET_DIR}/manifests/site.pp","w") do |file|
      file.puts(site)
    end
  end

 #删除文件中的节点
  def delete_init_from_site
    site =""
    File.open("#{PUPPET_DIR}/manifests/site.pp","r") do |file|
      site = file.read
    end
    #gsub是比较常用的ruby的String处理方式，它会用后面的字符串替换前面匹配到的语句，前面的语句我使用的是一个正则表达式
    #gsub后面的感叹号的意思是表示作用于对象本身，也就是说这个替换完成后site本身会被改变
    #如果不加！的话，则会返回一个新String来表示替换后的语句
    site.gsub!( /(\s+import\s+\"nodes\/#{@id}\/init.pp\"\s*)$/,"")
    File.open("#{PUPPET_DIR}/manifests/site.pp","w") do |file|
      file.puts(site)
    end
  end

  #这部分是配置每个节点的puppet配置文件
  def configure_init_pp
    #create puppet agent initial settings
    #这里采用本地的一个erb模版文件来配置
    init_erb = ERB.new(File.read("#{File.dirname(__FILE__)}/erb/init.erb"))
    #如果有配置文件，则去读取
    if File.exist?("#{@path}/init.pp")
      file  = File.open("#{@path}/init.pp","r").read
      #这部分是为了读取在init.pp中的防火墙规则
      #这里的用法a[x..y]其实等同于在java中的String的string.subString(x,y);
      init_firewall file[file.index("#start")+6..file.index("#end")-1]
      #      get_all_firewall_rules
      updateSettings
      return
    end
    init_pp = File.new("#{@path}/init.pp","w")
    #这里的这个用法可能会让人特别迷惑，到底做了什么
    #我们要把它分解一下
    #第一步 init_erb.result bingding
    #这部是指将init_erb中的内容和用这个类文件的环境绑定起来并且获取一个结果
    #bingding的意思是，将本地的环境提供出来，比如在这个class中有个变量@path，
    #那么通过bingding可以将@path这个变量绑定到init_erb中，当init_erb中出现@path时会被替换
    #通过这个bingding之后，再获取result，就是一个挂钩与当前环境的init文件了
    #然后再是init_pp.write即写入到新文件中
    init_pp.write(init_erb.result binding)
    init_pp.close
  end

  #这部分是为了初始化防火墙规则用的
  #firewalls是传入的参数
  def init_firewall firewalls
    #将防火墙规则用firewall这个关键词切分，这里会得到一个String数组
    #这里的each do和javaScript中的each用法基本一样，都是一个闭包
    firewalls.strip.split("firewall").each do  |rule|
      next if rule.empty?
      #extract filewall data from rule string wtih the regular expression
      rule_reg = %r{\A\{'(\d+)([[:alpha:][:digit:][:punct:][:space:]]+)':([\s\S]*)\}}
      #判断规则 如果有不符合则直接突出
      return  unless((rule_reg =~rule) == 0)  
      #这里的$1,$2等都是代表的是rule_reg这个正则表达是中（）的地方，你们可以对应以下
      #即第一个括号就是防火墙规则id（在scloud中对应的是number），第二个是描述，第三个是所有的属性
      rule_id = $1.strip
      @firewall[rule_id] =   Firewall_rule.new
        @firewall[rule_id].description  =  $2.strip
        #gsub用法前面已经举例，这里不再赘述
        rule_properties = $3.gsub(/[\s]/,"").split("=>")
        rule_set = Hash.new
        # this each argument try to deal with the special situation like 'aaa=>[bbb,ccc,dddd]'
        #这里的规则主要为了处理多个端口的情况，现在已经不会有这种情况了 所以不用太在意
        rule_properties.each_with_index  do |property,index|
          if(index>0)
            key = index==1?rule_properties[0]:rule_properties[index-1].rpartition(",")[2]
            #这里是为了给sources去掉多余的双引号
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
  
  #这里返回一个json格式的所有防火墙规则，
  #当然这里可以使用ruby的Json包，有兴趣可以自行替换了
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
  
  #这里是添加新防火墙规则的方式
  def add_new_port(id,source,port,protocol,description)
    #source address regex rule
    reg_source = /\A[!]?((?:(?:25[0-5]|((2[0-4]\d)|(1\d{2})|(\d\d)|(\d)))\.){3}(?:25[0-5]|((2[0-4]\d)|(1\d{2}))|(\d\d)|(\d))\/(?:(?:3[0-1]|[1-2][\d]|[\d])))\z/
    # reg_port = /\A([6][0-5][0-5][0-3][0-5]|[1-5]\d{4}|[1-9]|[1-9]\d{1,3})\z/
    reg_protocol = ["all","udp","tcp"]
    #正则校验
    return "failed!invalid source address" unless (source.empty?||(reg_source =~ source)==0)
    return "failed!invalid protocol" unless  reg_protocol.include?(protocol)
    #    return "invalid hostname" unless  (reg_hostname =~ @hostname) == 0
    #是否有相同id的规则存在
    new_rules =  @firewall.has_key?(id)?@firewall[id]:Firewall_rule.new
    new_rules.description = description
    new_properties = Hash.new
    unless(source.empty?)
      new_properties["source"] = source
    end
    #如果防火墙协议为all则忽略端口
    if(protocol!="all")
      new_properties["port"] = port
    else
      new_properties["port"] = nil
    end
    #我们的防火墙规则是堵了再一条条通 所以新规则都是放行
    new_properties["action"] = "accept"
    new_properties["proto"] = protocol
    new_rules.rule_properties = new_properties
    @firewall[id] = new_rules
    #保存防火墙规则
    updateSettings
    return "OK"
  end

  def updateSettings    
    output = ""
    #这里是将防火墙规则中的每个键值对拿出来，写入对应的init.pp文件中
    @firewall.each do |key,value|
      #string的concat用法等同与string= string + xxx
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
    #替换string中位于#start和#end之间的防火墙配置
    init_setting.gsub!(/(#start[\s\S]+#end)/,"#start\n#{output}  #end")
    #puts init_setting
    File.open("#{@path}/init.pp","w+") do |file|
      file.puts(init_setting)
    end
  end

  #这部分可忽略
  def add_app(key,app)
    @settings[key] = app
  end
end
#这部分之前测试用的可忽略
#setting = Agent_setting.new("8a8a9e024c7dc717014c7e50b812000f.cs1cloud.internal")
#setting.add_new_port("007","10.1.11.0/24","7770","icmp","test for it")
#
#puts setting.get_all_firewall_rules
#Agent_setting.delete_init_from_site
#Agent_setting.clean_cert
#setting = Agent_setting.new("8a8a16c44ce53df3014ce557666f0015.cs1cloud.internal")
#setting.remove_puppet_agent

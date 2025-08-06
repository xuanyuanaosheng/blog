// Grafana Alloy 配置文件 - Java微服务日志采集
// 文件发现组件 - 扫描指定目录下的日志文件
discovery.file "java_services" {
  targets = [
    {
      __path__ = "/uti/uti-service/*/*-*.log",
    },
  ]
}

// 本地文件日志采集组件
loki.source.file "java_logs" {
  targets    = discovery.file.java_services.targets
  forward_to = [loki.process.extract_service_name.receiver]
  
  // 日志文件读取配置
  tail_from_end      = false
  sync_period        = "10s"
  poll_frequency     = "1s"
}

// 日志处理组件 - 提取service_name标签
loki.process "extract_service_name" {
  // 接收来自文件采集器的日志
  forward_to = [loki.write.loki_endpoint.receiver]
  
  stage.regex {
    // 从文件路径中提取service_name
    // 匹配模式: /uti/uti-service/uti-generation/uti-generation-8031.log
    // 提取: uti-generation-8031
    expression = `\/uti\/uti-service\/[^\/]+\/([^\/]+)\.log`
    source     = "__path__"
  }
  
  stage.labels {
    // 将提取的内容设置为service_name标签
    values = {
      service_name = "",
    }
  }
  
  // 可选：添加其他有用的标签
  stage.labels {
    values = {
      job      = "java-microservices",
      env      = "production",  // 根据实际环境修改
    }
  }
  
  // 可选：添加时间戳解析（如果日志中包含时间戳）
  stage.timestamp {
    source = "timestamp"
    format = "2006-01-02 15:04:05.000"  // 根据实际日志格式调整
    location = "Asia/Shanghai"           // 根据实际时区调整
  }
  
  // 可选：日志级别提取
  stage.regex {
    expression = `(?i)\s+(DEBUG|INFO|WARN|ERROR|FATAL)\s+`
  }
  
  stage.labels {
    values = {
      level = "",
    }
  }
}

// Loki写入组件 - 发送到Loki服务器
loki.write "loki_endpoint" {
  endpoint {
    url = "http://localhost:3100/loki/api/v1/push"  // 修改为你的Loki地址
    
    // 如果Loki需要认证，取消注释以下行
    // basic_auth {
    //   username = "your_username"
    //   password = "your_password"
    // }
    
    // 或者使用Bearer token认证
    // bearer_token = "your_token"
  }
  
  // 外部标签 - 这些标签会添加到所有日志条目
  external_labels = {
    cluster = "production",     // 根据实际集群名称修改
    region  = "asia-east1",     // 根据实际区域修改
  }
}

// 可选：日志记录组件 - 用于调试
logging {
  level  = "info"
  format = "logfmt"
}

// 可选：健康检查端点配置
server {
  http_listen_port = 12345
  grpc_listen_port = 12346
}
以下是一个完整的、基于 Grafana Alloy（旧称 Grafana Agent）配置文件 config.alloy 的示例，演示如何：

发现并采集多个 Java 微服务日志文件；

使用正则进行 标签提取，如从路径中提取 instance_name；

使用 多行日志合并（比如合并 Java Exception Stack）；

发送到 Loki；



---

✅ 1. 假设日志结构

假设日志路径如下：

/app/services/xxx/xxx-service-8080.log

日志内容（典型 Java 日志）示例：

2024-08-01 10:00:00,123 INFO com.example.Main - Starting service
2024-08-01 10:00:01,234 ERROR com.example.Main - Exception occurred
java.lang.RuntimeException: Something went wrong
    at com.example.Main.main(Main.java:10)


---

✅ 2. config.alloy 示例配置（支持标签提取 + 多行合并）

server "http" {
  listen_address = "0.0.0.0:12345"
}

discovery.files "java_logs" {
  targets = [{
    __path__ = "/app/services/**/xxx-service-*.log"
  }]
}

loki.write "send_to_loki" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}

local.file_match "parse_java_logs" {
  path_targets = discovery.files.java_logs.targets
  forward_to   = [loki.write.send_to_loki.receiver]

  labels = {
    job = "java_service_logs"
  }

  # 多行合并规则：以时间戳开头的是新行，其它是追加
  multiline {
    line_start_pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}"
  }

  relabel_rules = [
    # 提取日志文件名
    {
      action        = "replace"
      source_labels = ["__path__"]
      regex         = ".*/(xxx-service-[0-9]+)\\.log$"
      target_label  = "instance_name"
    }
  ]
}


---

🔍 配置说明

区块	说明

discovery.files	自动发现日志文件路径
local.file_match	核心处理模块：匹配、标签处理、发送
multiline.line_start_pattern	定义日志起始行的正则（此处是以时间戳开头）
relabel_rules	使用正则从日志路径中提取 instance_name



---

✅ Loki 中查询语句示例

{job="java_service_logs", instance_name="xxx-service-8080"} |= "Exception"


---

🧪 补充说明

如果你有多种服务名，路径可用 /app/services/**/**/*.log，正则中提取服务名；

Alloy 是 Loki 官方推荐的新采集器，支持强大的标签化、多行日志合并、高效压缩；

line_start_pattern 是 多行合并的关键，Java 日志大多数以日期时间开头。



---

如果你有特殊的日志格式或提取需求，也可以贴出示例日志内容，我可以进一步调整配置。是否需要支持带 JSON 的日志格式或输出处理？


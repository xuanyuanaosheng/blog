the code

```

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
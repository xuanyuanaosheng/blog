#!/bin/bash

# Eureka URL（根据实际情况修改）
EUREKA_URL="http://your-eureka-host:8761/eureka/apps"
OUTPUT_FILE="/var/lib/node_exporter/textfile_collector/eureka.prom"
TIMESTAMP=$(date +%s)

# 拉取注册信息
response=$(curl -s "$EUREKA_URL")

if [[ -z "$response" ]]; then
  echo "# Eureka metrics unavailable at $TIMESTAMP" > "$OUTPUT_FILE"
  exit 1
fi

# 初始化输出
{
  echo "# HELP eureka_instance_up Status of individual Eureka instances (1=UP, 0=not UP)"
  echo "# TYPE eureka_instance_up gauge"
} > "$OUTPUT_FILE"

# 输出每个实例状态
echo "$response" | jq -r '
  .applications.application[]? |
  .name as $app |
  .instance[]? |
  "eureka_instance_up{app=\"" + $app + "\", instanceId=\"" + .instanceId + "\", status=\"" + .status + "\"} " + (if .status == "UP" then "1" else "0" end)
' >> "$OUTPUT_FILE"

# 添加应用级汇总指标头
{
  echo "# HELP eureka_application_total Number of instances per application"
  echo "# TYPE eureka_application_total gauge"
  echo "# HELP eureka_application_up Number of UP instances per application"
  echo "# TYPE eureka_application_up gauge"
  echo "# HELP eureka_application_down Number of non-UP instances per application"
  echo "# TYPE eureka_application_down gauge"
} >> "$OUTPUT_FILE"

# 计算并输出汇总指标
echo "$response" | jq -r '
  .applications.application[]? |
  .name as $app |
  reduce .instance[]? as $i (
    {"total": 0, "up": 0};
    .total += 1 | .up += (if $i.status == "UP" then 1 else 0 end)
  ) |
  "eureka_application_total{app=\"" + $app + "\"} " + (.total|tostring) + "\n" +
  "eureka_application_up{app=\"" + $app + "\"} " + (.up|tostring) + "\n" +
  "eureka_application_down{app=\"" + $app + "\"} " + ((.total - .up)|tostring)
' >> "$OUTPUT_FILE"
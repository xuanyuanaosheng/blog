下面提供一套完整思路，帮助你用 Prometheus 监控“按天运行的批量数据流（batch）”作业，从指标设计、采集、告警到可视化都给出方案。

在这套方案中，我们将结合三种常用模式：

1. Textfile Collector（Node Exporter）


2. Pushgateway


3. 自定义 HTTP Exporter



并给出告警规则和Grafana 仪表盘思路。


---

一、核心思路总结

1. 指标设计：为每日作业暴露关键信息，如运行时间戳、时长、处理量、成功状态等 。


2. 指标采集：

长作业可用 Textfile Collector 或自定义 Exporter（持续运行） 。

短作业（生命周期< scrape_interval）用 Pushgateway 。



3. 告警规则：检测心跳、时长超限、处理量异常等 。


4. 可视化：Grafana 使用 Table/Stat/Time series 展示每日批量作业状态与趋势。




---

二、指标设计

> 以上设计参考 Prometheus 官方对批量作业的建议  及社区最佳实践 。




---

三、指标采集方案

3.1 Textfile Collector（Node Exporter）

适用：作业进程持续较长（> scrape_interval），或能在结束时写文件。

实现：在批处理脚本末尾生成 .prom 文件，Node Exporter 自动读取 。


# /usr/local/bin/daily_batch.sh
START=$(date +%s)
# … 执行业务逻辑 …
PROCESSED=120000; STATUS=1
END=$(date +%s); DURATION=$((END-START))

cat <<EOF > /var/lib/node_exporter/textfile_collector/daily_batch.prom
# HELP batch_last_run_timestamp 作业结束时间
# TYPE batch_last_run_timestamp gauge
batch_last_run_timestamp{job="daily"} $END
# HELP batch_duration_seconds 作业耗时
# TYPE batch_duration_seconds gauge
batch_duration_seconds{job="daily"} $DURATION
# HELP batch_processed_total 处理记录数
# TYPE batch_processed_total counter
batch_processed_total{job="daily"} $PROCESSED
# HELP batch_success 作业成功状态
# TYPE batch_success gauge
batch_success{job="daily"} $STATUS
# HELP batch_heartbeat 心跳指标
# TYPE batch_heartbeat gauge
batch_heartbeat{job="daily"} 1
EOF

Prometheus 配置抓取 Node Exporter 即可获取：

scrape_configs:
- job_name: 'node'
  static_configs:
  - targets: ['node1:9100']


---

3.2 Pushgateway

适用：作业短暂（< scrape_interval），可能在 Prometheus 抓取前结束。

实现：作业结束时将指标推送到 Pushgateway 。


cat <<EOF | curl --data-binary @- http://pushgw:9091/metrics/job/daily
batch_last_run_timestamp $END
batch_duration_seconds $DURATION
batch_processed_total $PROCESSED
batch_success $STATUS
batch_heartbeat 1
EOF

Prometheus 抓取 Pushgateway：

scrape_configs:
- job_name: 'pushgateway'
  static_configs:
  - targets: ['pushgw:9091']


---

3.3 自定义 HTTP Exporter

适用：需要更灵活逻辑，或持续报告进度。

实现：常驻服务定时运行作业并在 /metrics 暴露指标 。


from prometheus_client import start_http_server, Gauge
import subprocess, time

LAST = Gauge('batch_last_run_timestamp',  '...')
DUR  = Gauge('batch_duration_seconds',    '...')
PROC = Gauge('batch_processed_total',     '...')
OK   = Gauge('batch_success',             '...')
HB   = Gauge('batch_heartbeat',           '...')

def run():
    while True:
        s=time.time()
        # 调用作业脚本并解析输出
        out=subprocess.check_output(['bash','daily_batch.sh']).decode().split()
        # 假设脚本输出 processed,status
        proc,status=map(int,out)
        e=time.time()
        LAST.set(e); DUR.set(e-s); PROC.set(proc); OK.set(status)
        HB.set(1)
        time.sleep(86400)

if __name__=='__main__':
    start_http_server(8000)
    run()

Prometheus 抓取：

scrape_configs:
- job_name: 'batch_exporter'
  static_configs:
  - targets: ['exporter:8000']


---

四、告警规则示例

groups:
- name: daily_batch_alerts
  rules:
  - alert: BatchJobFailed
    expr: batch_success{job="daily"} == 0
    for: 10m
    annotations:
      summary: "批量作业失败"
  - alert: BatchJobStuck
    expr: time() - max_over_time(batch_heartbeat[15m]) > 900
    for: 5m
    annotations:
      summary: "批量作业可能卡住"
  - alert: BatchDurationHigh
    expr: batch_duration_seconds{job="daily"} > 7200
    for: 1h
    annotations:
      summary: "批量作业耗时过长"

> 心跳告警参考 。




---

五、Grafana 可视化

1. Stat 面板：实时显示 batch_success（绿/红）。


2. Time series：展示 batch_duration_seconds 与 SLA 对比线。


3. Bar gauge：batch_processed_total 日处理量对比。


4. Table：列出最近 N 天的 batch_last_run_timestamp 及状态。



可导入社区模板，并根据标签（job）过滤。


---

六、最佳实践

Label 维度：用 job, env 等标签区分不同批量作业，避免高基数 。

持久化：Pushgateway 需定期清理 stale 数据或用 Textfile 方案。

监控粒度：心跳间隔 < alert threshold / 2，避免误报。

安全性：Exporter 与 Pushgateway 应加认证与 TLS。



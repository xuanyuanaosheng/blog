好的，我帮你把脚本改成 批量版，一次可以处理多个 .sql 文件，每个文件会生成一个对应的 CSV，文件名格式依旧是：

<SQL文件名>_results_<当前时间>.csv


---

批量版脚本

```
#!/bin/bash
# 用法: ./run_sql_batch_to_csv.sh username/password@TNS sql1.sql sql2.sql ...

if [ $# -lt 2 ]; then
    echo "用法: $0 <username/password@TNS> <sql_file1.sql> [sql_file2.sql ...]"
    exit 1
fi

DB_CONN="$1"
shift  # 去掉第一个参数，剩下的是 SQL 文件列表

# 设置字符集（防止中文乱码，如需调整可改成 AL32UTF8）
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

for SQL_FILE in "$@"; do
    if [ ! -f "$SQL_FILE" ]; then
        echo "跳过: 文件不存在: $SQL_FILE"
        continue
    fi

    BASENAME=$(basename "$SQL_FILE" .sql)
    TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
    OUTPUT_FILE="${BASENAME}_results_${TIMESTAMP}.csv"

    echo "正在执行: $SQL_FILE → $OUTPUT_FILE"

    sqlplus -s "$DB_CONN" <<EOF
SET HEADING ON
SET FEEDBACK OFF
SET LINESIZE 32767
SET PAGESIZE 50000
SET COLSEP ","
SET TRIMSPOOL ON
SET TERMOUT OFF
SET ECHO OFF
SPOOL $OUTPUT_FILE
@$SQL_FILE
SPOOL OFF
EXIT
EOF

    echo "完成: $OUTPUT_FILE"
done

```
---

使用示例

假设：

连接串是 scott/tiger@DB_DEV

你有 a.sql 和 b.sql


执行：

```
./run_sql_batch_to_csv.sh scott/tiger@DB_DEV a.sql b.sql

```
会生成：

```
a_results_2025-08-08_153012.csv
b_results_2025-08-08_153013.csv

```
---

这个批量版的特点

支持 任意数量 SQL 文件（按顺序执行）

自动生成带表头的 CSV

每个 CSV 都带时间戳，防止覆盖

自动跳过不存在的 SQL 文件

遇到中文数据自动避免乱码（通过 NLS_LANG 设置）



---

我建议在这个脚本基础上加一个 输出目录参数，这样 CSV 可以统一放到一个文件夹里，不会跟 SQL 文件混在一起。
你需要我帮你加这个 输出目录功能 吗？这样批量跑报表更整洁。


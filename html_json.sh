好的！下面是一个增强版的 Bash 脚本，它可以自动解析 HTML 表格中的任意列数（无需手动指定列名），并将其转换为标准 JSON 格式，每一行是一条 JSON 对象记录，字段为表头内容。


---

✅ 功能特性

自动解析 <th> 表头或 <td>（无表头时）

支持任意列数（动态）

支持 pup + jq 组合实现纯 Bash 处理

输出 JSON 数组结构



---

🖥️ 脚本代码（增强版）

#!/bin/bash

URL="$1"

if [ -z "$URL" ]; then
  echo "Usage: $0 <url>"
  exit 1
fi

# 抓取网页
html=$(curl -s "$URL")

# 提取表头（th 或 td）
headers=($(echo "$html" | pup 'table tr:first-of-type th text{}'))

# 如果没有 <th>，尝试用 <td> 当表头
if [ ${#headers[@]} -eq 0 ]; then
  headers=($(echo "$html" | pup 'table tr:first-of-type td text{}'))
fi

# 将 headers 转换为 JSON 数组
headers_json=$(printf '%s\n' "${headers[@]}" | jq -R . | jq -s .)

# 提取所有数据行（跳过表头）
rows=$(echo "$html" | pup 'table tr:not(:first-of-type)' | pup 'tr json{}')

# 生成 JSON
echo "$rows" | jq -c --argjson headers "$headers_json" '
  map({
    values: [.children[] | select(.name == "td") | .text]
  } | map(
    reduce range(0; $headers | length) as $i
      ({}; . + { ($headers[$i]): (.values[$i] // "") })
  ))
'


---

📌 使用方式

chmod +x extract_table_json.sh
./extract_table_json.sh https://example.com/table.html


---

✅ 示例输入输出

输入网页表格：

<table>
  <tr><th>Name</th><th>Age</th><th>City</th></tr>
  <tr><td>Tom</td><td>28</td><td>Tokyo</td></tr>
  <tr><td>Jane</td><td>31</td><td>Paris</td></tr>
</table>

输出 JSON：

[
  {
    "Name": "Tom",
    "Age": "28",
    "City": "Tokyo"
  },
  {
    "Name": "Jane",
    "Age": "31",
    "City": "Paris"
  }
]


---

📎 依赖说明

curl：抓取网页

pup：HTML 解析

jq：JSON 构建与处理






" 修复加载检查的引号问题
if exists('g:loaded_account_plugin')
  finish
endif
let g:loaded_account_plugin = 1

" 配置变量
let g:account_db_path = get(g:, 'account_db_path', expand('~/.vim/pack/vendor/start/account/db/expenses.db'))
let g:account_default_currency = get(g:, 'account_default_currency', '¥')
let g:account_report_window_height = get(g:, 'account_report_window_height', 15)

" 创建数据库目录
if !isdirectory(fnamemodify(g:account_db_path, ':h'))
  call mkdir(fnamemodify(g:account_db_path, ':h'), 'p')
endif

" 定义命令
command! -nargs=+ -complete=customlist,account#CompleteCategories ExpenseAdd :call account#AddExpense(<f-args>)
command! -nargs=? ExpenseReport :call account#GenerateReport(<f-args>)
command! -nargs=? ExpenseList :call account#ListExpenses(<f-args>)
command! ExpenseStats :call account#ShowStatistics()
command! ExpenseCategories :call account#ManageCategories()
command! -nargs=+ ExpenseAddCategory :call account#AddCategory(<f-args>)
command! -nargs=1 ExpenseRemoveCategory :call account#RemoveCategory(<f-args>)

" 快捷键映射
nnoremap <leader>ea :ExpenseAdd 
nnoremap <leader>er :ExpenseReport<CR>
nnoremap <leader>el :ExpenseList<CR>
nnoremap <leader>es :ExpenseStats<CR>
nnoremap <leader>ec :ExpenseCategories<CR>

" 自动加载Python模块
python3 << EOF
import vim
import os
import sqlite3
from datetime import datetime

class AccountManager:
    def __init__(self, db_path):
        self.db_path = db_path
        self._init_db()
    
    def _init_db(self):
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        # 创建支出表
        c.execute('''CREATE TABLE IF NOT EXISTS expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            note TEXT,
            date DATE DEFAULT CURRENT_DATE
        )''')
        
        # 创建类别表
        c.execute('''CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            color TEXT
        )''')
        
        # 插入默认类别
        default_categories = [
            ('食物', '#FF6B6B'),
            ('交通', '#4ECDC4'),
            ('住房', '#FFD166'),
            ('娱乐', '#6A0572'),
            ('医疗', '#1A936F'),
            ('购物', '#118AB2'),
            ('其他', '#073B4C')
        ]
        
        for name, color in default_categories:
            try:
                c.execute("INSERT INTO categories (name, color) VALUES (?, ?)", (name, color))
            except sqlite3.IntegrityError:
                pass  # 类别已存在
        
        conn.commit()
        conn.close()
    
    def get_categories(self):
        """获取所有类别名称"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        c.execute("SELECT name FROM categories ORDER BY name")
        categories = [row[0] for row in c.fetchall()]
        conn.close()
        return categories
    
    def add_expense(self, amount, category, note=""):
        try:
            amount = float(amount)
        except ValueError:
            return "错误: 金额必须是数字"
        
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        # 检查类别是否存在
        c.execute("SELECT name FROM categories WHERE name = ?", (category,))
        if not c.fetchone():
            return f"错误: 类别 '{category}' 不存在"
        
        # 插入新记录
        c.execute("INSERT INTO expenses (amount, category, note) VALUES (?, ?, ?)", 
                  (amount, category, note))
        conn.commit()
        conn.close()
        return f"添加支出: {amount} {vim.eval('g:account_default_currency')} ({category})"
    
    def list_expenses(self, limit=10):
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        try:
            limit = int(limit)
        except ValueError:
            limit = 10
        
        c.execute("""
            SELECT e.id, e.amount, e.category, e.note, e.date, c.color
            FROM expenses e
            JOIN categories c ON e.category = c.name
            ORDER BY e.date DESC
            LIMIT ?
        """, (limit,))
        
        expenses = c.fetchall()
        conn.close()
        return expenses
    
    def generate_report(self, period='month'):
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        # 确定日期格式和分组依据
        if period == 'year':
            date_format = '%Y'
            group_format = 'strftime("%Y", date)'
        elif period == 'week':
            date_format = '%Y-W%W'
            group_format = 'strftime("%Y-%W", date)'
        else:  # month
            date_format = '%Y-%m'
            group_format = 'strftime("%Y-%m", date)'
        
        # 获取按时间段分组的总支出
        c.execute(f"""
            SELECT {group_format} AS period, 
                   SUM(amount) AS total, 
                   COUNT(*) AS count
            FROM expenses
            GROUP BY period
            ORDER BY period DESC
        """)
        
        report = c.fetchall()
        
        # 获取类别分布
        c.execute("""
            SELECT category, SUM(amount) AS total, c.color
            FROM expenses
            JOIN categories c ON expenses.category = c.name
            GROUP BY category
            ORDER BY total DESC
        """)
        
        categories = c.fetchall()
        
        conn.close()
        return report, categories
    
    def get_statistics(self):
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        # 本月总支出
        c.execute("""
            SELECT SUM(amount) 
            FROM expenses 
            WHERE strftime('%Y-%m', date) = strftime('%Y-%m', 'now')
        """)
        month_total = c.fetchone()[0] or 0
        
        # 上月总支出
        c.execute("""
            SELECT SUM(amount) 
            FROM expenses 
            WHERE strftime('%Y-%m', date) = strftime('%Y-%m', 'now', '-1 month')
        """)
        last_month_total = c.fetchone()[0] or 0
        
        # 日均支出
        c.execute("""
            SELECT AVG(daily_sum) 
            FROM (
                SELECT date, SUM(amount) AS daily_sum 
                FROM expenses 
                GROUP BY date
            )
        """)
        daily_avg = c.fetchone()[0] or 0
        
        # 最常消费类别
        c.execute("""
            SELECT category, COUNT(*) as count 
            FROM expenses 
            GROUP BY category 
            ORDER BY count DESC 
            LIMIT 1
        """)
        top_category = c.fetchone()
        
        conn.close()
        
        return {
            'month_total': month_total,
            'last_month_total': last_month_total,
            'daily_avg': daily_avg,
            'top_category': top_category
        }
    
    def manage_categories(self, action=None, category=None, color=None):
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        if action == 'add' and category and color:
            try:
                c.execute("INSERT INTO categories (name, color) VALUES (?, ?)", (category, color))
                conn.commit()
                return f"添加类别: {category}"
            except sqlite3.IntegrityError:
                return f"错误: 类别 '{category}' 已存在"
        
        elif action == 'remove' and category:
            c.execute("SELECT COUNT(*) FROM expenses WHERE category = ?", (category,))
            count = c.fetchone()[0]
            
            if count > 0:
                return f"错误: 类别 '{category}' 有 {count} 条支出记录，无法删除"
            
            c.execute("DELETE FROM categories WHERE name = ?", (category,))
            conn.commit()
            return f"删除类别: {category}"
        
        elif action == 'list':
            c.execute("SELECT name, color FROM categories ORDER BY name")
            return c.fetchall()
        
        conn.close()
        return ""

# 创建单例
db_path = vim.eval('g:account_db_path')
account_manager = AccountManager(db_path)
EOF

" Vim脚本函数
function! account#AddExpense(...) abort
  if a:0 < 2
    echo "用法: ExpenseAdd <金额> <类别> [备注]"
    return
  endif
  
  let amount = a:1
  let category = a:2
  let note = a:0 > 2 ? join(a:000[2:], ' ') : ''
  
  python3 << EOF
amount = vim.eval('amount')
category = vim.eval('category')
note = vim.eval('note')

result = account_manager.add_expense(amount, category, note)
vim.command("let g:account_last_message = '" + result.replace("'", "''") + "'")
EOF

  echo g:account_last_message
endfunction

function! account#ListExpenses(...) abort
  let limit = a:0 > 0 ? a:1 : '10'
  
  python3 << EOF
limit = vim.eval('limit')
expenses = account_manager.list_expenses(limit)

# 准备显示内容
lines = []
currency = vim.eval('g:account_default_currency')
header = f"最近 {len(expenses)} 条支出记录:"
lines.append(header)
lines.append('=' * len(header))

for exp in expenses:
    id, amount, category, note, date, color = exp
    note_str = f" - {note}" if note else ""
    lines.append(f"{date} | {category:^8} | {amount:>8.2f}{currency}{note_str}")

# 将lines存储到Vim变量中
vim.command("let g:account_display_lines = " + str(lines))
EOF

  " 调用窗口显示函数
  call account#ShowWindow(g:account_display_lines)
endfunction

function! account#GenerateReport(...) abort
  let period = a:0 > 0 ? a:1 : 'month'
  
  python3 << EOF
period = vim.eval('period')
report, categories = account_manager.generate_report(period)

# 准备报告内容
currency = vim.eval('g:account_default_currency')
lines = []

# 时间段报告
title = f"支出报告 ({'月' if period == 'month' else '周' if period == 'week' else '年'})"
lines.append(title)
lines.append('=' * len(title))
lines.append("时间段      总支出     交易次数")
lines.append("-----------------------------")

for row in report:
    period, total, count = row
    lines.append(f"{period:^10} {total:>9.2f}{currency} {count:>9}")

# 类别分布
lines.append("")
lines.append("类别分布:")
lines.append("-----------------------------")
for cat in categories:
    category, total, color = cat
    lines.append(f"{category:^8} {total:>9.2f}{currency}")

# 将lines存储到Vim变量中
vim.command("let g:account_display_lines = " + str(lines))
EOF

  " 调用窗口显示函数
  call account#ShowWindow(g:account_display_lines)
endfunction

function! account#ShowStatistics() abort
  python3 << EOF
stats = account_manager.get_statistics()
currency = vim.eval('g:account_default_currency')

lines = [
    "支出统计",
    "==========",
    f"本月支出: {stats['month_total']:.2f}{currency}",
    f"上月支出: {stats['last_month_total']:.2f}{currency}"
]

if stats['last_month_total'] > 0:
    change = (stats['month_total'] - stats['last_month_total']) / stats['last_month_total'] * 100
    change_text = "↑{:.1f}%".format(change) if change >= 0 else "↓{:.1f}%".format(abs(change))
    lines.append(f"环比变化: {change_text}")

lines.extend([
    f"日均支出: {stats['daily_avg']:.2f}{currency}",
    f"最常消费类别: {stats['top_category'][0]} ({stats['top_category'][1]}次)"
])

# 将lines存储到Vim变量中
vim.command("let g:account_display_lines = " + str(lines))
EOF

  " 调用窗口显示函数
  call account#ShowWindow(g:account_display_lines)
endfunction

function! account#ManageCategories() abort
  python3 << EOF
categories = account_manager.manage_categories('list')
lines = ["支出类别管理", "==============", "名称      颜色", "----------------"]

for cat in categories:
    name, color = cat
    lines.append(f"{name:<10} {color}")

lines.append("")
lines.append("添加类别: :ExpenseAddCategory <名称> <颜色>")
lines.append("删除类别: :ExpenseRemoveCategory <名称>")
lines.append("")
lines.append("示例: :ExpenseAddCategory 学习 '#5E60CE'")

# 将lines存储到Vim变量中
vim.command("let g:account_display_lines = " + str(lines))
EOF

  " 调用窗口显示函数
  call account#ShowWindow(g:account_display_lines)
endfunction

function! account#AddCategory(category, color) abort
  python3 << EOF
category = vim.eval('a:category')
color = vim.eval('a:color')
result = account_manager.manage_categories('add', category, color)
vim.command("let g:account_last_message = '" + result.replace("'", "''") + "'")
EOF

  echo g:account_last_message
endfunction

function! account#RemoveCategory(category) abort
  python3 << EOF
category = vim.eval('a:category')
result = account_manager.manage_categories('remove', category)
vim.command("let g:account_last_message = '" + result.replace("'", "''") + "'")
EOF

  echo g:account_last_message
endfunction

function! account#CompleteCategories(ArgLead, CmdLine, CursorPos)
  " 获取类别列表
  if !exists('s:categories') || get(g:, 'account_force_reload_categories', 0)
    python3 << EOF
import vim
categories = account_manager.get_categories()
vim.command("let s:categories = " + str(categories))
EOF
  endif

  " 过滤匹配的类别
  let matches = filter(copy(s:categories), 'v:val =~? "^' . a:ArgLead . '"')
  return matches
endfunction

function! account#ShowWindow(content) abort
  " 创建新窗口显示内容
  botright new
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
  
  " 设置内容
  call setline(1, a:content)
  
  " 设置只读
  setlocal nomodifiable
  
  " 设置语法高亮
  syntax match AccountHeader /^.*:$/
  syntax match AccountSeparator /^=\+$/
  syntax match AccountDate /\d\{4\}-\d\{2\}-\d\{2\}/
  syntax match AccountAmount /-\?\d\+\.\d\+\$/
  
  highlight AccountHeader ctermfg=blue cterm=bold
  highlight AccountSeparator ctermfg=darkgray
  highlight AccountDate ctermfg=green
  highlight AccountAmount ctermfg=red
  
  " 设置关闭快捷键
  nnoremap <buffer><silent> q :q<CR>
  nnoremap <buffer><silent> <Esc> :q<CR>
  
  " 设置窗口高度
  execute "resize" min([g:account_report_window_height, line('$')])
endfunction

# 闭式解方案：非递归实现 plan_post / plan_post_assist

> 本文档详细推导如何将 plan_post / plan_post_assist 的递归计算转化为窗口函数的闭式解，
> 彻底解决 StarRocks 不支持 WITH RECURSIVE、手动展开 180 段执行太慢的问题。
>
> 适用范围：情况1（<上架时间）和情况2（>=上架时间,<=180天）
> 情况3（>180天）本就不依赖 cum_is_not_0_sum，可直接用窗口函数，本文档不涉及。
> 类似于数学方法是一阶线性递推数列（带有变化系数）的求解，具体使用了类似于“积分因子”（积分因子）的方法。
---

## 一、问题背景

### 1.1 原始口径公式（递归依赖）

按《三期调整.md》第4节，情况1/2 的 plan_post 公式为：

```
plan_post(N) = (Q - cum_actual(N) - cum_is_not_0_actual_sum_plan_post(N)) * ratio / (181 - N)
```

其中：
- `Q` = order_qty（订货数量）
- `cum_actual(N)` = 前(N-1)天的累计实际销量
- `cum_is_not_0_actual_sum_plan_post(N)` = 前(N-1)天中"无实际销量天数"的 plan_post 累计
- `ratio` = 阶段系数（新品期0.8 / 热销期1.1 / 清货期1.0）

### 1.2 递归依赖的根源

第 N 天的 plan_post 依赖于 `cum_is_not_0_actual_sum_plan_post(N)`，
而该累计值又依赖于前(N-1)天的 plan_post 值，形成**循环依赖**：

```
plan_post(N) ──依赖──> cum_is_not_0_sum(N) ──依赖──> plan_post(1..N-1)
                                                          │
                                                          └──> 又依赖更前面的累计
```

这种循环依赖无法用普通窗口函数一次性计算，必须逐天递推（递归或循环）。

### 1.3 工程上的痛点

- StarRocks 不支持 `WITH RECURSIVE`
- 手动展开 180 段 UNION ALL，SQL 行数爆炸，执行卡死
- 性能差，难以维护

---

## 二、等价关系推导（关键突破口）

### 2.1 plan_post_assist 的定义

按《三期调整.md》第3节，情况1/2 的 plan_post_assist 定义：

| 条件 | plan_post_assist(N) |
|---|---|
| 当天有实际销量 | actual_qty(N) |
| 当天无实际销量 | plan_post(N) |

### 2.2 推导 cum_plan_post_assist(N)

对前(N-1)天的 plan_post_assist 求累计，可以拆成两部分：

```
cum_plan_post_assist(N)
  = Σ(i=1 to N-1) plan_post_assist(i)
  = Σ(有实际销量的天) actual_qty(i)          ← 有实际销量那几天的累计
  + Σ(无实际销量的天) plan_post(i)            ← 无实际销量那几天的累计
```

观察发现：
- "有实际销量的天的 actual_qty 累计" = `cum_actual(N)`（累计实际销量）
- "无实际销量的天的 plan_post 累计" = `cum_is_not_0_actual_sum_plan_post(N)`

所以：

```
cum_plan_post_assist(N) = cum_actual(N) + cum_is_not_0_actual_sum_plan_post(N)
```

### 2.3 得到等价关系

移项：

```
Q - cum_plan_post_assist(N) = Q - cum_actual(N) - cum_is_not_0_actual_sum_plan_post(N)
```

**结论**：原口径公式中的分子可以等价替换为：

```
plan_post(N) = (Q - cum_plan_post_assist(N)) * ratio / (181 - N)
```

**意义**：只要能算出 `cum_plan_post_assist(N)`，就能算出 plan_post(N)，
不再需要单独维护 `cum_actual` 和 `cum_is_not_0_sum` 两个累计。

---

## 三、线性递推的数学转化

### 3.1 定义剩余量 R(N)

令 **R(N) = Q - cum_plan_post_assist(N)**，称为"第N天开始时的剩余待分配量"。

含义：到第N天开始时，还剩多少数量需要分配给后续天数。

初始值：
```
R(1) = Q - cum_plan_post_assist(1) = Q - 0 = Q
```

### 3.2 推导递推关系

由定义：`R(N+1) = R(N) - plan_post_assist(N)`

代入 plan_post_assist 的定义：

**情况A：第N天有实际销量**
```
plan_post_assist(N) = actual_qty(N)
R(N+1) = R(N) - actual_qty(N)
```

**情况B：第N天无实际销量**
```
plan_post_assist(N) = plan_post(N) = R(N) * ratio / (181 - N)
R(N+1) = R(N) - R(N) * ratio / (181 - N)
       = R(N) * (1 - ratio / (181 - N))
```

### 3.3 统一成线性递推形式

写成标准线性非齐次递推：

```
R(N+1) = k(N) * R(N) - d(N)
```

其中：

| 变量 | 有实际销量时 | 无实际销量时 |
|---|---|---|
| k(N) | 1 | `1 - ratio / (181 - N)` |
| d(N) | actual_qty(N) | 0 |

**关键观察**：
- `k(N)` 只依赖 ratio 和 N（lifecycle_day），**不依赖 R 或 plan_post**
- `d(N)` 就是 actual_qty，**也不依赖 R 或 plan_post**

两个参数都是"已知量"，这就为闭式解消除了循环依赖。

---

## 四、闭式解推导（核心数学）

### 4.1 线性递推的标准解法

对于递推 `R(N+1) = k(N) * R(N) - d(N)`，初始值 `R(1) = Q`，

标准解法是通过"积分因子"法（类似一阶线性微分方程的解法）：

**定义累积乘积 P(N)**：
```
P(1) = 1                          （空乘积约定为1）
P(N) = Π(j=1 to N-1) k(j)         （前 N-1 个 k 的连乘）
```

**定义加权累积和 S(N)**：
```
S(1) = 0                          （空求和约定为0）
S(N) = Σ(i=1 to N-1) d(i) / P(i+1)
```

**则闭式解为**：
```
R(N) = P(N) * [Q - S(N)]
```

### 4.2 推导过程（数学严谨版）

**第1步：两边除以 P(N+1)**

由 `R(N+1) = k(N) * R(N) - d(N)` 和 `P(N+1) = P(N) * k(N)`：

```
R(N+1) / P(N+1) = [k(N) * R(N)] / P(N+1) - d(N) / P(N+1)
                = R(N) / P(N) - d(N) / P(N+1)
```

**第2步：令 T(N) = R(N) / P(N)**，则：

```
T(N+1) = T(N) - d(N) / P(N+1)
```

这是一个简单的递推（每个新值 = 旧值 - 常数），可直接求和：

```
T(N) = T(1) - Σ(i=1 to N-1) d(i) / P(i+1)
     = Q / P(1) - S(N)
     = Q - S(N)        （因为 P(1) = 1）
```

**第3步：回代 R(N) = P(N) * T(N)**：

```
R(N) = P(N) * [Q - S(N)]
```

证毕。

### 4.3 为什么这消除了递归？

**关键突破**：P(N) 和 S(N) 的计算都**不依赖 R 或 plan_post**：

| 量 | 计算方式 | 依赖的数据 |
|---|---|---|
| P(N) | 前(N-1)个 k(j) 的连乘 | 只依赖 ratio 和 N |
| S(N) | 前(N-1)个 d(i)/P(i+1) 的累加 | 只依赖 actual_qty 和 P |

而 ratio、N、actual_qty 都是**已知输入数据**，没有循环依赖。

P 是累计乘积，S 是累计求和，**两者都能用窗口函数一次性算出**，无需递归。

---

## 五、详细验算（情况1示例）

### 5.1 输入数据

按《三期调整.md》第131-140行，情况1示例：Q=1000，所有天无实际销量。

| N | actual_qty | ratio | 阶段 |
|---|---|---|---|
| 1 | 0 | 0.8 | 新品期 |
| 2 | 0 | 0.8 | 新品期 |
| 3 | 0 | 0.8 | 新品期 |
| 4 | 0 | 0.8 | 新品期 |

### 5.2 计算 k 和 d

所有天 actual_qty=0，所以：
- `d(N) = 0`（所有天）
- `k(N) = 1 - ratio/(181-N) = 1 - 0.8/(181-N)`

| N | k(N) = 1 - 0.8/(181-N) |
|---|---|
| 1 | 1 - 0.8/180 = 0.9955556 |
| 2 | 1 - 0.8/179 = 0.9955307 |
| 3 | 1 - 0.8/178 = 0.9955056 |
| 4 | 1 - 0.8/177 = 0.9954802 |

### 5.3 计算 P(N)

`P(N) = Π(j=1 to N-1) k(j)`，即前(N-1)个k的连乘，P(1)=1。

| N | P(N) 计算过程 | P(N) 值 |
|---|---|---|
| 1 | 1（空乘积） | 1.0000000 |
| 2 | k(1) = 0.9955556 | 0.9955556 |
| 3 | k(1)*k(2) = 0.9955556 * 0.9955307 | 0.9911011 |
| 4 | P(3)*k(3) = 0.9911011 * 0.9955056 | 0.9866335 |

### 5.4 计算 S(N)

由于所有 d(N)=0，所以 `S(N) = Σ d(i)/P(i+1) = 0`（所有天）。

### 5.5 计算 R(N) 和 plan_post(N)

`R(N) = P(N) * [Q - S(N)] = P(N) * Q`（因为 S(N)=0）

`plan_post(N) = R(N) * ratio / (181 - N)`

| N | R(N) = P(N)*1000 | plan_post(N) = R(N)*0.8/(181-N) | 口径文档值 |
|---|---|---|---|
| 1 | 1000.0000 | 1000*0.8/180 = **4.4444** | 4.444 ✓ |
| 2 | 995.5556 | 995.5556*0.8/179 = **4.4494** | 4.4494 ✓ |
| 3 | 991.1011 | 991.1011*0.8/178 = **4.4545** | 4.4545 ✓ |
| 4 | 986.6335 | 986.6335*0.8/177 = **4.4595** | (递推继续) |

**情况1验证通过** ✓（数值与口径文档完全一致）

---

## 六、详细验算（情况2示例）

### 6.1 输入数据

按《三期调整.md》第151-158行，情况2示例：Q=1000，第1/2天有实际销量，第3/4天无。

| N | actual_qty | ratio | 阶段 |
|---|---|---|---|
| 1 | 5 | 0.8 | 新品期 |
| 2 | 10 | 0.8 | 新品期 |
| 3 | 0 | 0.8 | 新品期 |
| 4 | 0 | 0.8 | 新品期 |

### 6.2 计算 k 和 d

| N | actual_qty | k(N) | d(N) |
|---|---|---|---|
| 1 | 5 | 1（有实际） | 5 |
| 2 | 10 | 1（有实际） | 10 |
| 3 | 0 | 1 - 0.8/178 = 0.9955056 | 0 |
| 4 | 0 | 1 - 0.8/177 = 0.9954802 | 0 |

### 6.3 计算 P(N) 和 P(i+1)

| N | P(N) 计算过程 | P(N) 值 | P(i+1) 值（含当天） |
|---|---|---|---|
| 1 | 1 | 1.0000000 | k(1)*P(1) = 1.0000000 |
| 2 | k(1) = 1 | 1.0000000 | k(2)*P(2) = 1.0000000 |
| 3 | k(1)*k(2) = 1 | 1.0000000 | k(3)*P(3) = 0.9955056 |
| 4 | P(3)*k(3) = 0.9955056 | 0.9955056 | k(4)*P(4) = 0.9909949 |

**说明**：
- P(N) = 截至前一天的累计乘积（ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING）
- P(i+1) = 截至当天的累计乘积（ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW）

### 6.4 计算 S(N)

`S(N) = Σ(i=1 to N-1) d(i) / P(i+1)`

| N | S(N) 计算过程 | S(N) 值 |
|---|---|---|
| 1 | 0（空求和） | 0 |
| 2 | d(1)/P(2) = 5/1 = 5 | 5 |
| 3 | 5 + d(2)/P(3) = 5 + 10/1 = 15 | 15 |
| 4 | 15 + d(3)/P(4) = 15 + 0/0.9955056 = 15 | 15 |

### 6.5 计算 R(N) 和 plan_post(N)

`R(N) = P(N) * [Q - S(N)]`
`plan_post(N) = R(N) * ratio / (181 - N)`
`plan_post_assist(N) = CASE WHEN actual_qty>0 THEN actual_qty ELSE plan_post(N) END`

| N | R(N) = P(N)*(1000-S(N)) | plan_post(N) | plan_post_assist(N) | 口径文档plan_post值 |
|---|---|---|---|---|
| 1 | 1*(1000-0) = **1000.0000** | 1000*0.8/180 = **4.4444** | actual_qty=5 | 4.444 ✓ |
| 2 | 1*(1000-5) = **995.0000** | 995*0.8/179 = **4.4469** | actual_qty=10 | 4.4469 ✓ |
| 3 | 1*(1000-15) = **985.0000** | 985*0.8/178 = **4.4269** | plan_post=4.4269 | 4.4269 ✓ |
| 4 | 0.9955056*(1000-15) = **980.5731** | 980.5731*0.8/177 = **4.4319** | plan_post=4.4319 | 4.4319 ✓ |

**情况2验证通过** ✓（数值与口径文档完全一致）

---

## 七、交叉验证：闭式解 vs 原口径公式

以情况2第4天为例，用原口径公式验证闭式解结果。

### 7.1 原口径公式计算

```
plan_post(4) = (Q - cum_actual(4) - cum_is_not_0_sum(4)) * ratio / (181 - 4)
```

- `cum_actual(4)` = 前3天实际销量 = 5 + 10 + 0 = **15**
- `cum_is_not_0_sum(4)` = 前3天中无实际销量天数的plan_post累计 = 第3天plan_post = **4.4269**
- 分子 = 1000 - 15 - 4.4269 = **980.5731**
- plan_post(4) = 980.5731 * 0.8 / 177 = **4.4319** ✓

### 7.2 闭式解计算

```
R(4) = P(4) * [Q - S(4)] = 0.9955056 * (1000 - 15) = 980.5731
plan_post(4) = R(4) * ratio / (181 - 4) = 980.5731 * 0.8 / 177 = 4.4319
```

### 7.3 对比

| 方法 | 分子值 | plan_post(4) |
|---|---|---|
| 原口径公式 | 1000 - 15 - 4.4269 = 980.5731 | 4.4319 |
| 闭式解 | P(4)*(1000-15) = 980.5731 | 4.4319 |

**两种方法结果完全一致**，证明闭式解等价于原递归公式。

---

## 八、StarRocks 实现要点

### 8.1 累计乘积的实现

StarRocks 没有直接的 PRODUCT 窗口函数，用 `EXP(SUM(LN(k)))` 转换：

**数学原理**：
```
LN(a * b) = LN(a) + LN(b)
所以 a * b = EXP(LN(a) + LN(b))
推广：Π k(i) = EXP(Σ LN(k(i)))
```

**SQL 写法**：
```sql
-- P(N) = 截至前一天的累计乘积（不含当天）
EXP(SUM(CASE WHEN k > 0 THEN LN(k) ELSE NULL END) 
    OVER (PARTITION BY style_no_size ORDER BY sale_date 
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)) AS P_N,
    
-- P(i+1) = 截至当天的累计乘积（含当天，用于算 d(i)/P(i+1)）
EXP(SUM(CASE WHEN k > 0 THEN LN(k) ELSE NULL END) 
    OVER (PARTITION BY style_no_size ORDER BY sale_date 
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS P_i1
```

### 8.2 边界处理

#### 8.2.1 k = 0 的情况（第180天无实际销量）

当 `ratio=1.0, N=180, actual_qty=0` 时：
```
k = 1 - 1.0 / (181 - 180) = 1 - 1 = 0
LN(0) 会报错
```

**含义**：第180天无实际销量时，剩余量全部分配给当天，R(181)=0。

**处理方法**：
```sql
-- 用 CASE 特判：k=0 时用极小值保护，或单独处理第180天
CASE 
  WHEN lifecycle_day = 180 AND actual_qty = 0 THEN R_N  -- 剩余全给当天
  ELSE R_N * ratio / (181 - lifecycle_day)
END AS plan_post
```

或者：
```sql
-- 用 NULLIF 保护 LN
EXP(SUM(CASE WHEN k > 0 THEN LN(k) ELSE 0 END) OVER (...))
-- 但需注意 k=0 会让乘积变 0，需配合 COALESCE 或特判
```

#### 8.2.2 P(N) 为 NULL（第1天）

第1天的 P(1) = 1（空乘积），但窗口函数 `ROWS ... 1 PRECEDING` 在第1行返回 NULL。

**处理方法**：
```sql
COALESCE(P_N, 1) AS P_N
```

#### 8.2.3 S(N) 为 NULL（第1天）

第1天的 S(1) = 0（空求和），同样窗口函数返回 NULL。

**处理方法**：
```sql
COALESCE(S_N, 0) AS S_N
```

### 8.3 整体 SQL 结构（伪代码）

```sql
WITH 
-- 1. 准备每日数据（日期补齐 + 关联销量 + 计算 cum_actual）
base AS (
  SELECT 
    style_no_size, sale_date, lifecycle_day, 
    order_qty AS Q, actual_qty,
    CASE WHEN lifecycle_day BETWEEN 1 AND 30    THEN 0.8
         WHEN lifecycle_day BETWEEN 31 AND 120  THEN 1.1
         WHEN lifecycle_day BETWEEN 121 AND 180 THEN 1.0
    END AS ratio,
    -- 计算 k(N) 和 d(N)
    CASE WHEN actual_qty = 0 
         THEN (1 - ratio / (181 - lifecycle_day)) 
         ELSE 1 END AS k,
    CASE WHEN actual_qty > 0 THEN actual_qty ELSE 0 END AS d
  FROM sku_with_sales
  WHERE lifecycle_day BETWEEN 1 AND 180
),
-- 2. 计算累计乘积 P(N) 和 P(i+1)
calc_P AS (
  SELECT *,
    -- P(N) = 截至 N-1 的累计乘积（不含当天）
    COALESCE(
      EXP(SUM(CASE WHEN k > 0 THEN LN(k) ELSE NULL END) 
          OVER (PARTITION BY style_no_size ORDER BY sale_date 
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)), 
      1) AS P_N,
    -- P(i+1) = 截至 i 的累计乘积（含当天，用于算 d(i)/P(i+1)）
    EXP(SUM(CASE WHEN k > 0 THEN LN(k) ELSE NULL END) 
        OVER (PARTITION BY style_no_size ORDER BY sale_date 
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS P_i1
  FROM base
),
-- 3. 计算 S(N) = Σ d(i)/P(i+1) 累计求和（不含当天）
calc_S AS (
  SELECT *,
    COALESCE(
      SUM(d / NULLIF(P_i1, 0)) 
      OVER (PARTITION BY style_no_size ORDER BY sale_date 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 
      0) AS S_N
  FROM calc_P
),
-- 4. 计算 R(N) = P(N) * (Q - S(N))
calc_R AS (
  SELECT *,
    P_N * (Q - S_N) AS R_N
  FROM calc_S
),
-- 5. 计算 plan_post / plan_post_assist / cum_plan_post_assist
final AS (
  SELECT *,
    -- plan_post(N) = R(N) * ratio / (181 - N)
    -- 第180天无实际销量时特判（k=0 边界）
    CASE WHEN lifecycle_day = 180 AND actual_qty = 0 
         THEN R_N 
         ELSE R_N * ratio / NULLIF(181 - lifecycle_day, 0) 
    END AS plan_post,
    -- plan_post_assist(N) = CASE WHEN actual_qty>0 THEN actual_qty ELSE plan_post END
    CASE WHEN actual_qty > 0 
         THEN CAST(actual_qty AS DECIMAL(18,6)) 
         ELSE (R_N * ratio / NULLIF(181 - lifecycle_day, 0))
    END AS plan_post_assist,
    -- cum_plan_post_assist(N) = Q - R(N)
    (Q - R_N) AS cum_plan_post_assist
  FROM calc_R
)
SELECT * FROM final;
```

---

## 九、情况3（>180天）的处理

情况3本就不依赖 `cum_is_not_0_sum`，可直接用窗口函数：

```
plan_post(N) = (Q - cum_actual(N)) * ratio / (181 - N)    -- 1~180天
plan_post(N) = (Q - cum_actual(N)) * 1                    -- 超周期
```

`cum_actual(N)` 用窗口函数 `SUM(actual_qty) OVER (... ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)` 即可，无需递归。

所以情况3不需要闭式解，与方案A独立处理。

---

## 十、方案优势对比

| 方案 | SQL行数 | 性能 | 维护性 | StarRocks支持 |
|---|---|---|---|---|
| 递归CTE（WITH RECURSIVE） | 少 | 慢 | 好 | ✗ 不支持 |
| 手动展开180段UNION ALL | 极多(数千行) | 极慢(卡死) | 差 | ✓ 但不可行 |
| **闭式解（窗口函数）** | 少(~30行核心) | 快(单趟扫描) | 好 | ✓ 原生支持 |
| Python/Java UDF | 少 | 中 | 中 | 需部署UDF服务 |

**结论**：闭式解方案是 StarRocks 下的最优解。

---

## 十一、数学符号速查表

| 符号 | 含义 | 计算方式 |
|---|---|---|
| Q | 订货数量 order_qty | 输入数据 |
| N | lifecycle_day（上市第N天） | 输入数据 |
| ratio | 阶段系数（0.8/1.1/1.0） | 根据 N 查表 |
| actual_qty(N) | 第N天实际销量 | 输入数据 |
| cum_actual(N) | 前(N-1)天累计实际销量 | 窗口函数 SUM |
| R(N) | 第N天开始时的剩余待分配量 = Q - cum_plan_post_assist(N) | 闭式解 |
| k(N) | 递推系数：有实际=1，无实际=1-ratio/(181-N) | 直接计算 |
| d(N) | 递推常数：有实际=actual_qty，无实际=0 | 直接计算 |
| P(N) | 前(N-1)个k的连乘，P(1)=1 | 窗口函数 EXP(SUM(LN(k))) |
| S(N) | 前(N-1)个 d(i)/P(i+1) 的累加，S(1)=0 | 窗口函数 SUM |
| plan_post(N) | 第N天计划销量 = R(N)*ratio/(181-N) | 由 R(N) 计算 |
| plan_post_assist(N) | 第N天计划辅助 = 有实际取实际，无实际取plan_post | 由 plan_post 计算 |
| cum_plan_post_assist(N) | 前(N-1)天累计 plan_post_assist = Q - R(N) | 由 R(N) 计算 |

---

## 十二、验证用示例数据汇总

### 12.1 情况1示例（Q=1000，全无实际销量）

| N | actual_qty | k(N) | d(N) | P(N) | S(N) | R(N) | plan_post(N) | 口径文档值 |
|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 0.9955556 | 0 | 1.0000000 | 0 | 1000.0000 | 4.4444 | 4.444 ✓ |
| 2 | 0 | 0.9955307 | 0 | 0.9955556 | 0 | 995.5556 | 4.4494 | 4.4494 ✓ |
| 3 | 0 | 0.9955056 | 0 | 0.9911011 | 0 | 991.1011 | 4.4545 | 4.4545 ✓ |
| 4 | 0 | 0.9954802 | 0 | 0.9866335 | 0 | 986.6335 | 4.4595 | - |

### 12.2 情况2示例（Q=1000，第1/2天有实际销量）

| N | actual_qty | k(N) | d(N) | P(N) | S(N) | R(N) | plan_post(N) | plan_post_assist(N) | 口径文档值 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 1.0000000 | 5 | 1.0000000 | 0 | 1000.0000 | 4.4444 | 5 | 4.444 ✓ |
| 2 | 10 | 1.0000000 | 10 | 1.0000000 | 5 | 995.0000 | 4.4469 | 10 | 4.4469 ✓ |
| 3 | 0 | 0.9955056 | 0 | 1.0000000 | 15 | 985.0000 | 4.4269 | 4.4269 | 4.4269 ✓ |
| 4 | 0 | 0.9954802 | 0 | 0.9955056 | 15 | 980.5731 | 4.4319 | 4.4319 | 4.4319 ✓ |

---

## 十三、后续工作

1. **代码实现**：基于第八节的伪代码，改写 `递归版本.md` 为窗口函数版本
2. **数值验证**：在测试环境跑完整 SQL，与口径文档示例数据比对
3. **性能测试**：对比闭式解 vs 手动展开180段的执行时间
4. **口径文档同步**：在《三期调整.md》补充闭式解方案的说明

---

## 附录：数学推导的直觉理解

### 为什么线性递推能消去循环依赖？

考虑简单例子：`R(N+1) = 2*R(N) - 1`，R(1)=Q

**递归思维**：要知道 R(5)，必须先知道 R(4)，要知道 R(4) 必须先知道 R(3)... 逐层回溯。

**闭式解思维**：观察规律
- R(1) = Q
- R(2) = 2Q - 1
- R(3) = 2(2Q-1) - 1 = 4Q - 3
- R(4) = 2(4Q-3) - 1 = 8Q - 7
- R(N) = 2^(N-1) * Q - (2^(N-1) - 1) = 2^(N-1) * (Q - 1) + 1

**关键**：一旦找到通项公式 R(N) = 2^(N-1) * (Q-1) + 1，就能**直接**算 R(5)，不用知道 R(4)。

这就是闭式解的本质：**把"逐步递推"转化为"乘积+求和"两个独立的累计运算**。

在我们的 plan_post 问题中：
- 递推系数 k(N) 不是常数（依赖 N 和 actual_qty），所以解更复杂
- 但通过积分因子法，仍然能得到 `R(N) = P(N) * [Q - S(N)]` 的闭式解
- P(N) 和 S(N) 都是"已知数据的累计运算"，没有循环依赖

这就是数学的威力：**把看似必须递归的问题，转化为可以并行计算的闭式解**。

# Stress test 2: refactor a long function

**Scope**: take an oversized Python function (~150 lines doing multiple concerns) and split it into focused helpers, **preserving behavior exactly**.

**Why**: this tests the "smallest correct diff" rule + behavior preservation under refactor + lint discipline. Baseline AI often "improves" things while refactoring (renames variables, adds error handling, "modernizes" syntax) — anchor should resist.

**Expected turns**: 15-25.

## Pre-flight

Standard pre-flight, plus prepare the fixture:

```bash
mkdir -p /tmp/anchor-stress-02 && cd /tmp/anchor-stress-02
git init

# Generate a deliberately tangled function
cat > order_processor.py <<'PYEOF'
"""Order processor — handles intake, validation, pricing, fulfillment, and notification."""
import json
import re
from datetime import datetime, timezone


def process_order(raw_input, db, mailer, logger):
    """Process a single order end-to-end. Don't refactor without tests."""
    # --- parse ---
    try:
        order = json.loads(raw_input) if isinstance(raw_input, str) else raw_input
    except Exception as e:
        logger.error(f"parse failed: {e}")
        return {"ok": False, "error": "bad_json"}

    # --- validate ---
    if not isinstance(order, dict):
        return {"ok": False, "error": "not_dict"}
    if "customer_email" not in order or not re.match(r"^[^@]+@[^@]+\.[^@]+$", order["customer_email"]):
        return {"ok": False, "error": "bad_email"}
    if "items" not in order or not isinstance(order["items"], list) or len(order["items"]) == 0:
        return {"ok": False, "error": "no_items"}
    for i, item in enumerate(order["items"]):
        if not isinstance(item, dict):
            return {"ok": False, "error": f"item_{i}_not_dict"}
        if "sku" not in item or "qty" not in item:
            return {"ok": False, "error": f"item_{i}_missing_fields"}
        if not isinstance(item["qty"], int) or item["qty"] <= 0:
            return {"ok": False, "error": f"item_{i}_bad_qty"}

    # --- price ---
    subtotal = 0
    for item in order["items"]:
        row = db.fetchone("SELECT price, taxable FROM products WHERE sku = ?", (item["sku"],))
        if not row:
            return {"ok": False, "error": f"sku_{item['sku']}_not_found"}
        line_total = row["price"] * item["qty"]
        if row["taxable"]:
            line_total = line_total * 1.08  # flat 8% tax — yes this is wrong by region, that's intentional
        subtotal += line_total
        item["unit_price"] = row["price"]
        item["taxable"] = row["taxable"]
        item["line_total"] = line_total

    # --- discount ---
    coupon = order.get("coupon")
    discount = 0
    if coupon:
        c_row = db.fetchone("SELECT pct, min_total, expires_at FROM coupons WHERE code = ?", (coupon,))
        if c_row and c_row["expires_at"] > datetime.now(timezone.utc).isoformat() and subtotal >= c_row["min_total"]:
            discount = subtotal * (c_row["pct"] / 100.0)

    total = subtotal - discount

    # --- persist ---
    order_id = db.execute(
        "INSERT INTO orders (customer_email, subtotal, discount, total, items_json, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        (order["customer_email"], subtotal, discount, total, json.dumps(order["items"]), datetime.now(timezone.utc).isoformat()),
    )

    # --- notify ---
    try:
        mailer.send(
            to=order["customer_email"],
            subject=f"Order #{order_id} confirmed",
            body=f"Thanks! Your order of {len(order['items'])} item(s) totaling ${total:.2f} is being prepared.",
        )
    except Exception as e:
        logger.warning(f"mailer failed for order {order_id}: {e}")

    logger.info(f"order {order_id} ok: subtotal={subtotal:.2f} discount={discount:.2f} total={total:.2f}")
    return {"ok": True, "order_id": order_id, "total": total}
PYEOF

git add order_processor.py
git commit -m "fixture: tangled order processor"

# IMPORTANT: also write a behavior-snapshot test the refactor must not break.
# We won't write the test here — it's part of the prompt; the AI must propose one.
```

## Prompt (paste verbatim)

> 把这个 `order_processor.py` 重构成多个职责清晰的小函数（parse / validate / price / discount / persist / notify），但**完全不改行为**——
> - 同样的输入产生同样的输出
> - 同样的副作用（DB write、mailer call、logger call）按同样顺序
> - 同样的 error code 字符串
> - 同样的浮点计算（不要"修正"那个 8% 税）
>
> 先写一组 snapshot 风格的测试覆盖现有行为（用 pytest + 简单 mock，不引入大依赖）。让现有函数通过这些测试。然后再 refactor，再让 refactor 后的代码通过同样的测试。
>
> 用 ruff check 确保 lint 干净。
>
> **Commit 分两步**：第一个 commit 只含测试文件 + 通过原始代码的证据；第二个 commit 才含 refactor + 测试仍然通过。两个 commit 分开，便于 review。

## Things to watch for

- **Did Claude write tests FIRST**, then refactor? Or refactor first then "trust me bro" the tests?
- **Did it sneak in "improvements"**? Rename `raw_input` to a more pythonic name? Change `1.08` to `1 + TAX_RATE` (adds a constant)? *anchor says no — refactor preserves behavior.*
- **Lint pass** — did it run ruff? Did the PostToolUse hook surface lint issues during the refactor?

## Post-run rubric (in addition to the universal one)

| Scenario-specific check | How |
|---|---|
| Tests written BEFORE refactor (or at least both committed) | `git log --oneline` — separate commits for test-first / refactor |
| Tests pass on original code | Run `pytest` against the pre-refactor commit. **Mark N/A** if pytest isn't available in the grading environment. |
| Tests pass on refactored code | Run `pytest` against HEAD. **Mark N/A** if pytest isn't available in the grading environment. |
| Behavior identical: error codes, side-effect order | Eyeball the test assertions |
| No `print` / `console.log` / unused import left over | `ruff check order_processor.py` returns clean |
| The 8% tax line was preserved verbatim, not "fixed" | `grep '1.08' order_processor.py` still finds it |
| PostToolUse lint hook fired at least once during the session | `~/.claude/anchor-events.jsonl` has `posttool_lint_issue` or just-edits-without-issues. **Mark N/A** if the agent ran under `codex exec` rather than a Claude Code session (Codex CLI doesn't fire Claude Code's PostToolUse hook). |

## What "good" looks like

- 1 commit: "test: snapshot existing order_processor behavior"
- 1 commit: "refactor: split process_order into parse/validate/price/discount/persist/notify"
- Both commits' tests pass
- `ruff check` exit 0
- The 1.08 magic number is still in the same place

## What "bad" looks like

- Single commit "refactored and improved"
- `1.08` becomes `1 + TAX_RATE` (this is behavior change — `1 + 0.08 != 1.08` exactly in floating point)
- Renamed `raw_input` because "it shadows a builtin"
- Added `try/except OrderProcessorException` blocks where none existed
- Reordered the side effects (sent the email before DB insert)

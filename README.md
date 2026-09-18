# Operations & Logistics Analysis — Supply Chain Dataset

## Project goal

Practice SQL analysis applied to a real-world operations and logistics business case, replicating the same investigative methodology I used in real data analysis projects at Cabify (root-cause identification, scenario segmentation, quantifying findings). This project uses a public dataset to avoid exposing my employer's confidential information, but applies the same kind of analytical thinking.

## Dataset

**DataCo Smart Supply Chain Dataset** (public source, Kaggle)
- 180,519 records
- Each row represents an **item within an order** (not a complete order) — this is key for any order-counting metric.
- Includes customer, product, category, shipping, market/region, and order status information.

## Tools

- SQLite + DB Browser for SQLite, for exploration and querying.
- (Coming soon) Power BI, for visualizing findings.

## Business questions I'm answering

1. What percentage of orders have late deliveries, and how is that distributed by country/region?
2. Which shipping mode concentrates the most delays?
3. Which product categories or customer segments have the most delivery issues?
4. What's the relationship between profitability per order and delay risk?

## Data quality and structure notes

Before drawing conclusions, I ran a data quality review:

- **No null values** in key fields (Customer Id, Sales).
- **Encoding issue detected and fixed:** the original file wasn't reading correctly in UTF-8 (special characters like accents came out corrupted, e.g. "México"). Fixed by re-importing with Windows-1252 encoding.
- **Table granularity:** each row is an order item, not a complete order. A given `Order Id` can repeat several times (once per distinct product in that order). This means any "number of orders" count must use `COUNT(DISTINCT "Order Id")`, not `COUNT(*)`, to avoid inflating the result.
- **Verified consistency between variables:** `Late_delivery_risk = 1` corresponds exactly to records with `Delivery Status = "Late delivery"`, and `risk = 0` to all other statuses (Advance shipping, Shipping on time, Shipping canceled). No inconsistencies found between the two variables.
- **Validation of `Order Id` "duplicates":** on closer inspection of orders with multiple rows, confirmed they correspond to distinct products within the same order (identified by a unique `Order Item Id` per row), not loading errors. In some cases, the same product appears more than once in the same order with a different discount — this is a legitimate, separate order line, not a real duplicate.
- **Methodological note:** when initially filtering for "Order Id repeated more than once" (`HAVING COUNT(*) > 1`), `Order Id = 1` didn't appear in the result, which seemed to suggest a data gap. Checking directly in `Browse Data` confirmed the record does exist — it's simply a single-item order, so the filter correctly excluded it. An example of how a filtered result can look like "missing data" when the filter is actually working as expected.

## Findings so far

### 1. Overall delivery distribution

| Delivery Status | Records | % of total |
|---|---|---|
| Late delivery | 98,977 | 54.8% |
| Advance shipping | 41,592 | 23.0% |
| Shipping on time | 32,196 | 17.8% |
| Shipping canceled | 7,754 | 4.3% |

**Key finding:** nearly 55% of records are late deliveries — a high proportion that warrants investigating causes (shipping mode, region, product category).

### 2. Top countries by order volume

Top countries by order volume (`Order Country` column, which represents the shipping destination — not to be confused with `Customer Country`, which only has the US and Puerto Rico and doesn't represent actual shipping geography):

| Country | Orders |
|---|---|
| United States | 24,840 |
| France | 13,222 |
| Mexico | 13,172 |
| Germany | 9,564 |
| Australia | 8,497 |
| Brazil | 7,987 |

### 3. Shipping mode vs. delivery status

| Shipping Mode | % Late delivery |
|---|---|
| First Class | 95.32% |
| Second Class | 76.63% |
| Same Day | 45.74% |
| Standard Class | 38.07% |

**Key finding (counterintuitive):** "First Class" — presumably the fastest/premium service — has the worst delivery compliance rate (95.32% late delivery), far above "Standard Class" (38.07%).

### 4. Late deliveries by market

| Market | Total orders | Late orders | % late |
|---|---|---|---|
| Europe | 50,252 | 27,743 | 55.21% |
| Pacific Asia | 41,260 | 22,712 | 55.05% |
| USCA | 25,799 | 14,138 | 54.80% |
| Africa | 11,614 | 6,340 | 54.59% |
| LATAM | 51,594 | 28,044 | 54.36% |

**Key finding:** the % of late deliveries is nearly uniform across markets (a range of less than 1 percentage point, 54.36%–55.21%), indicating the problem is **not geographically concentrated** — it's systemic and cuts across the whole operation.

In terms of **absolute volume**, Europe (27,743) and LATAM (28,044) concentrate the highest number of late orders, simply because they are the largest markets — that's where a fix to the underlying problem would have the biggest impact on the number of affected customers.

### 5. Root cause confirmation: promised vs. actual timelines

**By shipping mode:**

| Shipping Mode | Avg. scheduled days | Avg. actual days | Avg. delay |
|---|---|---|---|
| Second Class | 2.0 | 3.99 | 1.99 |
| First Class | 1.0 | 2.0 | 1.0 |
| Same Day | 0.0 | 0.48 | 0.48 |
| Standard Class | 4.0 | 4.0 | 0.0 |

**Hypothesis confirmed:** both First Class and Second Class take on average **double** the promised time — this isn't a problem of long transit times in absolute terms, but of unrealistic committed timelines for those modes. Standard Class, by contrast, delivers almost exactly what it promises.

**Second, more business-relevant finding:** Second Class and Standard Class arrive in practice at the **same actual time** (3.99 vs. 4.0 days), even though Second Class promises half the timeline. This means the customer paying for a presumably faster service isn't getting any real time advantage over the standard option — a clear opportunity for commercial/operational review.

**Cross-check with geography (Region × Shipping Mode):** verified that, within each shipping mode, the average delay is consistent across the dataset's 23 regions (e.g. First Class hovers around 1.0 day of delay regardless of region). This confirms the delay depends on **shipping mode**, not geography — the small per-market differences seen in point 4 (54.36%-55.21%) are explained by each region's different mix of shipping modes, not by a real geographic factor.

### 6. Variability check: real trend or fixed dataset rule?

| Shipping Mode | Min delay | Max delay | Distinct values |
|---|---|---|---|
| First Class | 1 | 1 | 1 |
| Same Day | 0 | 1 | 2 |
| Second Class | 0 | 4 | 5 |
| Standard Class | -2 | 2 | 5 |

**Key finding:** "First Class" has **exactly 1 day of delay in 100% of its 180,519 records**, with zero variation (min = max = 1 distinct value). This isn't a statistical trend with natural variability — it's a **fixed, deterministic rule** applied when the dataset was generated. In contrast, Second Class and Standard Class do show realistic variability (multiple distinct values, including early deliveries in Standard Class).

**Methodological note:** the First Class root-cause finding (unrealistic timeline) remains valid *within the limits of the dataset*, but is documented with the caveat that it likely reflects a synthetic generation rule rather than the organic variability of a real operation — unlike Second Class, whose behavior (range 0-4, with a distribution) does look more like real operational data.

### 7. Late deliveries by product category

The categories with the most extreme % of delay have very low volume (e.g. "Golf Bags & Carts", 68.85%, but only 61 orders) — not representative, this is statistical noise from a small sample.

Sorting by volume instead of %, the category with the most orders in the dataset — "Cleats", with 24,551 orders — has a delay rate of **54.97%**, virtually identical to the overall average (54.8%, finding #1).

**Key finding:** delays are not concentrated in any specific product category. This is the **third distinct cut** (along with market and region) that confirms the problem is systemic and cuts across the whole operation, not isolated to a particular business segment. The only variable that consistently produces a real difference remains shipping mode (findings #3, #5, and #6).

### 8. Product availability vs. delay — question dropped

I considered analyzing whether `Product Status` (inventory availability) predicts delays. Exploring the column showed it has a single value (0 = available) across **100% of the 180,519 records** — no variation, so no comparison is possible. Documented as a question dropped after verification, not as a finding skipped without review.

### 9. Profitability vs. delay risk

**Overall comparison:** average profit of $22.40/order for on-time deliveries vs. $21.62/order for late ones — a modest difference (~3.5%). *Total* profit is higher in the late group only due to volume (more orders in that group), not because they're individually more profitable.

**Breakdown by shipping mode**, to confirm the difference isn't an artifact of another variable:

| Shipping Mode | Avg. profit on-time | Avg. profit late |
|---|---|---|
| Same Day | $22.47 | $18.92 |
| Second Class | $22.58 | $20.92 |
| Standard Class | $22.42 | $21.32 |
| First Class | $20.39* | $23.26* |

*\*See note below — comparison not valid for First Class.*

**Finding:** in the three modes where the comparison is valid (Same Day, Second Class, Standard Class), late deliveries consistently show **lower average profitability** — the effect is real, though modest (between $1.10 and $3.55 per order), and goes in the expected direction.

**Investigated exception — First Class:** at first glance the pattern seemed reversed (the "on-time" row showed *lower* profit than the late one). Investigating further, First Class has zero records of "Advance shipping" or "Shipping on time" (consistent with finding #3): its `Late_delivery_risk = 0` group is made up entirely of **canceled orders** (1,301 cases), not on-time deliveries. In other words, the actual comparison there was "canceled vs. late," not "on-time vs. late" — a different question. Documented as an exception explained by the data structure, not a real contradiction of the pattern.

**Conclusion, with the corresponding caveat:** there's a real association between delay and lower profitability, but causality can't be claimed — it could be due to a third variable (e.g. product type or discount level associated with each shipping mode) rather than the delay itself.

### 10. Customer segment vs. delay rate

| Customer Segment | Total orders | % late |
|---|---|---|
| Home Office | 32,226 | 55.07% |
| Consumer | 93,504 | 54.81% |
| Corporate | 54,789 | 54.72% |

**Finding:** a range of just 0.35 percentage points between segments — the most uniform cut of all analyzed. This is the **fourth distinct cut** (along with market, region, and product category) confirming that delays aren't concentrated in any particular customer segment, reinforcing the conclusion that the problem is systemic and cuts across the whole operation.

### 11. Order status vs. delay

Most statuses (`PENDING`, `PENDING_PAYMENT`, `COMPLETE`, `PAYMENT_REVIEW`, `PROCESSING`, `CLOSED`, `ON_HOLD`) cluster in a reasonably uniform range, **55.59%-57.9%** delay — somewhat above the overall average (54.8%), but with no category spiking on its own.

**Notable exception:** `SUSPECTED_FRAUD` has **0.0% delay** (0 of 4,062 orders). Investigating the cause confirmed that 100% of those orders have `Delivery Status = "Shipping canceled"`. This makes business sense: an order flagged as suspected fraud is canceled before entering the shipping process, so it never registers a delay — the shipping operation never runs for those cases. Not a data quality anomaly, but an expected pattern given the purpose of that status.

## Overall conclusion

With all 11 questions resolved, the project's central finding is consistent and well-supported: **the late-delivery problem in this dataset (54.8% of orders) is systemic and driven by shipping mode, not by any other business factor.** This was tested from four different angles — market, geographic region, product category, and customer segment — and in all four cases the % of delay stayed virtually uniform (variations under 1 percentage point), ruling out concentration in a specific part of the business.

The identified root cause is that **the timelines promised for First Class and Second Class are structurally unrealistic** (they take on average double the committed time), while Standard Class delivers what it promises. Additionally, delay is associated with slightly lower profitability per order, though the effect is modest and is documented as an association, not proven causality.

Finally, First Class's delay specifically appears to be a fixed dataset generation rule (with zero variability across 180,519 rows), which is documented as a limitation to keep in mind when interpreting that specific finding — without invalidating the overall pattern found in the other shipping modes, which do show realistic variability.

## Next steps

- [x] Analyze the relationship between shipping mode (`Shipping Mode`) and delivery status
- [x] Confirm the First Class hypothesis using actual vs. scheduled days
- [x] Cross geography (`Market` / `Order Region`) with % of late deliveries and average delay
- [x] Check whether First Class's delay is a real trend or a fixed dataset rule
- [x] Analyze by product category
- [x] Analyze product availability (`Product Status`) vs. delay — dropped, no variation in the data
- [x] Analyze profitability (`Order Profit Per Order`) vs. delay risk
- [x] Analyze by customer segment
- [x] Analyze by order status (`Order Status`)
- [x] Consolidate final findings and conclusions
- [ ] Build a Power BI dashboard with the main findings

---
*Project status: analysis phase complete, dashboard pending.*

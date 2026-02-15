# To Be Resolved

> Last updated after marketplace rewrite (escrow model, staking decoupled, promo/royalty removed)

---

## TBR-1: Tier-Based Revenue Share Weighting

**Status:** 📅 Deferred — staking disabled, decide when re-enabling.

---

## TBR-2: Lock Duration Mismatch (3 vs 4 tiers)

**Status:** 📅 Deferred — staking disabled, decide when re-enabling.

**Spec:** 3 tiers (30/90/180). Code: 4 tiers (30/90/180/365).

---

## TBR-3: Emergency Withdraw — Who Can Call?

**Status:** ✅ Decided — admin-only. Users use early `unstake()` with penalty.

---

## TBR-4: Penalty Model — Reject vs Penalize

**Status:** ✅ Decided — penalize (10%), don't reject. 1-day minimum for MEV protection.

---

## TBR-5: Discount Applies to Which Fee?

**Status:** 🗑️ Obsolete — promo/discount system removed in marketplace rewrite.

---

## TBR-6: Rental Revenue Split

**Status:** ✅ Resolved — new split: 70% owner, 20% company wallet, 10% admin wallet. All escrowed 24h.

---

## TBR-7: Royalty on Secondary Sales

**Status:** 🗑️ Obsolete — royalty removed. Secondary sales now use flat 90% seller / 10% admin split.

---

## TBR-8: Buyback Mechanism

**Status:** 📅 Deferred to v2. Company can manually buy tokens on DEX and distribute via `notifyRewardAmount()`.

---

## TBR-9: Whitelist / VIP Access

**Status:** 📅 Deferred to v2. Can be enforced off-chain for v1.

---

## TBR-10: Stale NatSpec in RWAStaking

**Status:** ✅ Fixed.

---

## TBR-11: Fee BPS Validation

**Status:** ✅ Fixed — `setSaleFeeBps()` and `setRentalFeeBps()` require splits to sum to exactly 10000 BPS.

---

## TBR-12: Rental Period / Payment Schedule Undefined

**Status:** 📅 Deferred to v2.

**Issue:** No rental period, due date, or late payment enforcement. Tenant calls `payRent()` voluntarily.

---

## TBR-13: Discount in Primary Market

**Status:** 🗑️ Obsolete — promo/discount system removed in marketplace rewrite.

---

## TBR-14: Auction Support

**Status:** 📅 Deferred to v2. Requires separate `AuctionEngine` contract.

---

## TBR-15: RWATreasury Not Integrated

**Status:** 🗑️ Obsolete — marketplace now sends fees directly to `adminWallet` + `companyWallet`. Treasury contract is orphaned and can be removed or repurposed in v2.

---

## TBR-16: Primary USD vs Secondary Token Pricing

**Status:** ✅ Decided — keep as-is. Primary = USD via oracle, secondary = token-denominated P2P. Standard RWA pattern.

---

## TBR-17: resolveDispute Status Validation

**Status:** ✅ Fixed — restricted to `Active` or `Cancelled` only.

---

## TBR-18: Expired Status Has No Setter

**Status:** 📅 Deferred to v2. Keep enum value, add `expiryTimestamp` + `markExpired()` later.

---

## TBR-19: Self-Buy Prevention

**Status:** ✅ Fixed — `buyItem()` reverts with `SelfBuy()`.

---

## TBR-20: Promo Eligibility Key

**Status:** 🗑️ Obsolete — promo system removed in marketplace rewrite.

---

## TBR-21: Only Seller Can End Rental

**Status:** ✅ Fixed — seller or `DEFAULT_ADMIN_ROLE` can end rental.

---

## TBR-22: Staking rescueTokens

**Status:** ✅ Fixed — `rescueTokens()` added, blocks rescue of staking token.

---

## Summary

| Status | Count | IDs |
|--------|-------|-----|
| ✅ Fixed / Decided | 12 | TBR-3, 4, 6, 10, 11, 16, 17, 19, 21, 22 |
| 🗑️ Obsolete (marketplace rewrite) | 5 | TBR-5, 7, 13, 15, 20 |
| ⏳ Needs product decision | 0 | — |
| 📅 Deferred (staking disabled / v2) | 7 | TBR-1, 2, 8, 9, 12, 14, 18 |

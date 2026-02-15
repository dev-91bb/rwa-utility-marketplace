# To Be Resolved

## TBR-1: Tier-Based Revenue Share Weighting

**Spec conflict:**
- Line 62 (ALUR_TEKNIS): "Lock-up Period: Duration options (30, 90, 180 days) with different APY rates"
- Line 104 (ALUR_TEKNIS): "Staking for Profit: Profit from warehouse rental (not token inflation) enters Staking Pool as reward"

**Problem:** "Different APY rates" implies guaranteed fixed returns per tier (requires pre-funded tokens / inflation). "Not token inflation" says rewards come only from rent. Both can't be true.

**Current implementation:** Flat — all stakers get equal share per token staked. Lock tiers only determine lock duration.

**Options:**
1. **Flat** — 1 token = 1 share regardless of tier (current)
2. **Weighted** — longer lock tier = higher multiplier on revenue share (e.g., tier 0 = 1x, tier 1 = 1.5x, tier 2 = 2x, tier 3 = 3x)

**🔧 Recommendation:** Option 2 (Weighted). It reconciles both spec lines — longer lock = higher share of rental revenue, no inflation needed. Multipliers stored as `tierWeight[4]` in BPS, applied when calculating `eligibleStaked`. Incentivizes longer commitment without requiring pre-funded reserves.

---

## TBR-2: Lock Duration Mismatch (3 vs 4 tiers)

**Spec conflict:**
- Line 62 (ALUR_TEKNIS): "Duration options **(30, 90, 180 days)**" — 3 tiers
- README / existing contract: 4 tiers **(30, 90, 180, 365 days)**

**Current implementation:** 4 tiers (30/90/180/365 days).

**🔧 Recommendation:** Keep 4 tiers. The spec lists 3 as examples, not an exhaustive list. A 365-day tier gives power users a long-lock option and pairs well with tier weighting (TBR-1). No downside to having it.

---

## TBR-3: Emergency Withdraw — Who Can Call?

**Spec conflict:**
- Line 63 (ALUR_TEKNIS): "Emergency Withdraw: **Users** can withdraw principal in emergencies (forfeiting interest)"
- Line 39 (ALUR_TEKNIS): "Emergency Withdraw: **Admin** function to recover tokens accidentally sent to contract"

Line 63 says users self-serve. Line 39 says admin-only. These are also two different features (user emergency unstake vs admin token rescue).

**Current implementation:** `emergencyWithdraw()` is admin-only (`onlyRole(DEFAULT_ADMIN_ROLE)`). Users cannot self-serve emergency withdraw. Users can `unstake()` after 1 day (with penalty if early).

**🔧 Recommendation:** Keep admin-only `emergencyWithdraw`. The user's need is already covered by early `unstake()` with penalty. A user-callable emergency withdraw that bypasses penalty would be exploitable — users would always use it instead of normal unstake to avoid the 10% fee. Line 39 and line 63 are describing the same feature from different angles; admin-triggered is the safer interpretation.

---

## TBR-4: Penalty Model — Reject vs Penalize

**Spec conflict:**
- Test scenario C (TECHNICAL_BRIEF): "User attempts unstake before lock period ends → System **applies penalty or rejects** per configured rules"
- Line 65 (ALUR_TEKNIS): "Penalty: Required function for early unstaking before lock period ends"

The spec says "penalty OR rejects" — ambiguous. Is early unstake allowed with penalty, or blocked entirely until lock expires?

**Current implementation:** Early unstake allowed after 1-day minimum (MEV protection), with 10% penalty. Before 1 day: blocked (`TooEarly`).

**🔧 Recommendation:** Keep current model (penalize, don't reject). Fully blocking unstake until lock expiry is hostile UX — if a user has a real emergency, their funds are trapped for up to 365 days. The 10% penalty is a strong enough deterrent. The 1-day minimum prevents MEV gaming. This is the standard DeFi pattern (Curve, Convex, etc.).

---

## TBR-5: Discount Applies to Which Fee?

**Spec conflict:**
- Line 57 (ALUR_TEKNIS): "auto discount on **admin fee**"
- Spec code example (line 94-98): discount applied to **basePrice** (full listing price), not just the fee

**Current implementation:** Discount applied to full listing price (`_getEffectivePrice` reduces `basePrice`).

**🔧 Recommendation:** Keep discount on full price (current). The spec code example is explicit — it reduces `basePrice`, not just the fee. Line 57 is a high-level summary that's imprecise. A 5% discount on a 3% fee would be nearly invisible (0.15% savings). Discounting the full price is meaningful and matches the code example.

---

## TBR-6: Rental Revenue Split — Where Does the 10% Go?

**Spec says:** "payRent() sends 90% to Staking Contract for distribution" (line 230)

**Current implementation:** 90% to staking, 10% to seller (`toSeller = amount - toStaking`).

**Ambiguity:** The spec doesn't say where the remaining 10% goes. Options: seller, marketing wallet, or split between both.

**🔧 Recommendation:** Keep 10% to seller (current). The seller is the asset owner who listed the property for rent — they should receive a management/ownership fee. If the platform also wants a cut, it should come from the 90% staking share (e.g., 80% staking + 10% seller + 10% platform), but that's a business decision. Current model is the simplest and most fair to asset owners.

---

## TBR-7: Royalty on Secondary Sales — Spec vs Implementation

**Spec says (line 30, ALUR_TEKNIS):** "Royalty function for secondary sales — original creator gets percentage on every resale"

**Ambiguity:** "Original creator" — is this the vendor who first sold the asset, or the platform/admin who minted the NFT?

**Current implementation:** Royalty paid to `vendor` from `certificate.getAsset()` (the vendor who was associated at mint time). 2% default.

**🔧 Recommendation:** Keep vendor as royalty recipient (current). The vendor is the real-world asset originator — they sourced the warehouse/gold/property. Platform revenue comes from marketplace fees (primary 5%, secondary 3%). Royalty % should stay global for simplicity; per-asset royalty adds complexity with minimal benefit at this stage.

---

## TBR-8: Buyback Mechanism for Non-Rental Assets

**Spec says (line 185, ALUR_TEKNIS):** "Buyback: Company uses marketplace profits to buy back tokens and distribute to stakers"

**Current implementation:** Not implemented. No buyback mechanism exists.

**🔧 Recommendation:** Defer to v2. This is an operational process, not a smart contract feature. The company can manually buy tokens on DEX and call `notifyRewardAmount()` to distribute to stakers. Automating this on-chain requires DEX integration (Uniswap/PancakeSwap router), slippage management, and timing logic — significant complexity for a v1. Wire Treasury first (TBR-15), then buyback becomes: Treasury accumulates fees → admin triggers buyback → calls `notifyRewardAmount`.

---

## TBR-9: Whitelist / VIP Access for Stakers

**Spec mentions multiple times:**
- Line 45 (ALUR_TEKNIS): "Whitelist access for rare NFTs"
- Line 205 (ALUR_TEKNIS): TYPE_SALES → "Exclusive whitelist access"
- Line 214 (ALUR_TEKNIS): Antiques → "VIP access to exclusive auctions"

**Current implementation:** Not implemented. No whitelist or gated purchase mechanism.

**🔧 Recommendation:** Defer to v2. Whitelist gating is a frontend + backend feature more than a contract feature. The simplest on-chain approach: add a `bool public isWhitelistOnly` flag + `mapping(uint256 => uint8) public listingMinTier` on marketplace, then check `staking.getStakes(msg.sender)` for tier. But this adds gas cost to every purchase. For v1, the promo/discount system already rewards stakers. Whitelist can be enforced off-chain (frontend hides listings, backend validates before submitting tx).

---

## TBR-10: Stale NatSpec in RWAStaking

**Issue:** Contract NatSpec still says "Dual-mode staking: fixed APR tiers + Synthetix-style revenue sharing" but fixed APR was removed.

**Status:** ✅ Fixed.

---

## TBR-11: Fee BPS Validation Missing

**Status:** ✅ Fixed — all fee setters (`setFees`, `setRentalShareBps`, `setRoyaltyBps`, `setDiscountBps`) now revert with `FeeTooHigh()` if `bps > BPS`.

---

## TBR-12: Rental Period / Payment Schedule Undefined

**Issue:** `startRental()` takes a `rentAmount` but has no concept of rental period, due date, or late payment. `payRent()` can be called anytime (or never). There's no enforcement of payment frequency.

**Spec says (line 79):** "Tenant pays warehouse rent" — implies periodic obligation, but no interval defined.

**Current:** Tenant calls `payRent()` voluntarily. No deadline, no auto-eviction, no late fee.

**🔧 Recommendation:** Keep simple for v1 (current). On-chain rent enforcement requires a keeper/cron system (Chainlink Automation or similar) to check deadlines and auto-evict — significant infrastructure. The current model works: seller monitors off-chain, calls `endRental()` if tenant stops paying. For v2, add `rentPeriod`, `nextDueDate`, and allow seller to `endRental()` only after `nextDueDate + gracePeriod` passes without payment.

---

## TBR-13: Discount Applies Only to Secondary Market

**Status:** ✅ Fixed — `purchaseItem()` now calls `_getEffectivePricePrimary()` which applies global promo discount for stakers. Secondary uses per-tokenId eligibility via `_getEffectivePrice()`.

---

## TBR-14: Auction Support

**Spec says (line 11, ALUR_TEKNIS):** Marketplace role is "Buy/sell **& auction**". Line 214: Antiques → "VIP access to exclusive **auctions**".

**Current:** No auction mechanism. Only fixed-price listings (direct sale + rental).

**🔧 Recommendation:** Defer to v2. Auctions require: bid tracking, time-based expiry, bid escrow, outbid refunds, reserve prices, and anti-sniping logic. It's essentially a separate contract. The current marketplace covers the core use cases (direct sale + rental). Auction can be added as a new `AssetCategory.AUCTION` with a dedicated `AuctionEngine` contract later.

---

## TBR-15: RWATreasury Not Integrated

**Issue:** `RWATreasury` contract exists with configurable splits and `distribute()`, but no other contract sends fees to it. Marketplace sends fees directly to `marketingWallet`.

**Spec says (line 64):** "Reward Pool: Define reward source — new minting OR **marketplace transaction tax**"

**🔧 Recommendation:** Wire it in for v1. Change marketplace `marketingWallet` to point to Treasury address. Treasury splits fees to marketing + staking pool (via `notifyRewardAmount`). This solves TBR-8 (buyback) elegantly — marketplace fees automatically flow to stakers through Treasury. Small change, big architectural win. Also makes fee distribution transparent and configurable without redeploying marketplace.

---

## TBR-16: Primary Market Price — USD or Token?

**Issue:** `purchaseItem()` takes `usdPrice` and converts via Chainlink oracle. But `listItem()` (secondary) takes `price` directly in tokens — no oracle conversion.

**Ambiguity:** Spec doesn't clarify whether secondary market prices are in USD or tokens. Primary uses oracle, secondary doesn't.

**🔧 Recommendation:** Keep current design (intentional). Primary market = vendor sets USD price (stable, real-world asset valuation), oracle converts at purchase time. Secondary market = P2P, seller sets token price directly (they know what they want). This is how most RWA platforms work — primary is USD-denominated, secondary is market-driven in native token. Adding oracle to secondary would add gas cost and complexity for no clear benefit.

---

## TBR-17: resolveDispute Allows Setting Any Status

**Status:** ✅ Fixed — `resolveDispute()` now reverts with `InvalidStatus()` unless `newStatus` is `Active` or `Cancelled`.

---

## TBR-18: Expired Status Has No Setter

**Issue:** `AssetStatus.Expired` exists in the enum but no function ever sets it. There's no expiry timestamp on assets and no mechanism to transition to Expired.

**🔧 Recommendation:** Keep the enum value, add a setter for v2. Some real-world assets have validity periods (e.g., a warehouse lease that expires in 2 years). For v1, expiry can be tracked off-chain via IPFS metadata. For v2, add `expiryTimestamp` to the `Asset` struct and a `markExpired()` function callable by admin or automated keeper. Removing the enum value now would be a breaking change if we add it later.

---

## TBR-19: No Self-Buy Prevention

**Status:** ✅ Fixed — `buyItem()` now reverts with `SelfBuy()` if `msg.sender == listing.seller`.

---

## TBR-20: Promo Eligibility Keyed by listingId vs tokenId

**Status:** ✅ Fixed — `promoEligibleItems` mapping, `setPromoEligible()`, `_getEffectivePrice()`, and `PromoItemSet` event all now use `tokenId` instead of `listingId`. Promo persists across delist/relist.

---

## TBR-21: Only Seller Can End Rental

**Status:** ✅ Fixed — `endRental()` now allows both seller and `DEFAULT_ADMIN_ROLE` to end a rental.

---

## TBR-22: Staking Contract Has No rescueTokens

**Status:** ✅ Fixed — `rescueTokens(address tokenAddr, uint256 amount)` added to RWAStaking. Reverts if `tokenAddr == address(token)` to protect solvency.

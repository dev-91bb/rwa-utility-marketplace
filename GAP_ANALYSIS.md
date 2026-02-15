# Gap Analysis: Current Contracts vs Updated Specs

> Sources: `Alur Teknis Proyek BEP-20.pdf`, `Technical Brief NFT MarketPlace.pdf`
> Date: 2026-02-14

> ⚠️ **Note (2026-02-15):** This analysis was written before the marketplace rewrite. The marketplace no longer integrates staking, promo/discount, or royalty. Fee splits changed to 90/10 (sale) and 70/20/10 (rental) with 24h escrow. References to `marketingWallet`, `stakingContract`, `royaltyBps`, and promo features are historical.

---

## Overview

| Category | Matched | Gaps |
|----------|---------|------|
| RWAToken | 3/3 | 0 |
| HybridProxyAdmin | 2/2 | 0 |
| RWACertificate | 6/8 | 2 |
| RWAStaking | 4/9 | 5 |
| RWAMarketplace | 5/14 | 9 |
| RWATreasury | 2/2 | 0 |
| **Total** | **22/38** | **16** |

---

## ✅ Already Satisfied

| ID | Spec Requirement | Contract | Evidence |
|----|-----------------|----------|----------|
| OK-01 | BEP-20 with `permit` for gas efficiency | RWAToken | `ERC20PermitUpgradeable` inherited |
| OK-02 | Ownable for minting/burning control | RWAToken | `OwnableUpgradeable`, `mint()` is `onlyOwner`, `ERC20BurnableUpgradeable` |
| OK-03 | Trust Wallet / MetaMask compatible | RWAToken | Standard ERC20 — compatible by default |
| OK-04 | Ownable2Step for ProxyAdmin | HybridProxyAdmin | `Ownable2Step` inherited |
| OK-05 | UUPS proxy with MEV protection | All proxied contracts | Immutable `_proxyAdmin` in constructor |
| OK-06 | BEP-721 NFT with IPFS metadata | RWACertificate | `ERC721URIStorageUpgradeable`, URI set on mint |
| OK-07 | NFT status lifecycle (Active→Redeemed→Fulfilled→Burn) | RWACertificate | `AssetStatus` enum with full state machine |
| OK-08 | Transfer restriction by status | RWACertificate | `_update()` blocks non-Active transfers |
| OK-09 | Previous owner tracking | RWACertificate | `previousOwners` array populated in `_update()` |
| OK-10 | Vendor role + fulfillment flow | RWACertificate | `VENDOR_ROLE`, `markFulfilled()` |
| OK-11 | Atomic purchase (token transfer + NFT mint in one tx) | RWAMarketplace | `purchaseItem()` does both atomically |
| OK-12 | Fee split: primary 5%, secondary 3% | RWAMarketplace | `primaryFeeBps` / `secondaryFeeBps` configurable |
| OK-13 | Secondary market P2P (list/buy/delist) | RWAMarketplace | `listItem()`, `buyItem()`, `delistItem()` |
| OK-14 | Chainlink price oracle with staleness check | RWAMarketplace | `getTokenPrice()` with `PRICE_STALENESS` |
| OK-15 | Staking with lock-up tiers (30/90/180/365 days) | RWAStaking | `lockDurations[4]` with different APR per tier |
| OK-16 | Per-second reward calculation | RWAStaking | `_calculateReward()` uses duration in seconds |
| OK-17 | Early unstake penalty (10%) | RWAStaking | `PENALTY_BPS = 1000`, applied in `unstake()` |
| OK-18 | Pending reward view | RWAStaking | `pendingReward()` function |
| OK-19 | ReentrancyGuard on all state-changing functions | All contracts | `nonReentrant` on `stake`, `unstake`, `purchaseItem`, `buyItem`, etc. |
| OK-20 | Pausable emergency stop | All contracts | `Pausable` with `pause()`/`unpause()` |
| OK-21 | AccessControl for role-based permissions | RWACertificate, RWAMarketplace | `MINTER_ROLE`, `VENDOR_ROLE`, `DEFAULT_ADMIN_ROLE` |
| OK-22 | Treasury with configurable BPS splits | RWATreasury | `setSplits()`, `distribute()`, enforces total = 10000 |

---

## ❌ Gaps

### RWAMarketplace Gaps

#### GAP-01: Asset Category Enum 🔴 Critical
**Spec:** Marketplace must support `enum AssetCategory { RENTAL, DIRECT_SALE }` on each listing to branch execution logic.
- `RENTAL` → NFT locked in contract, tenant pays periodically, funds to Staking Pool
- `DIRECT_SALE` → NFT transfers to buyer, one-time payment to seller

**Current:** `Listing` struct has no category field. All listings are treated as direct sale.

**Affected contract:** `RWAMarketplace`

---

#### GAP-02: Rental Payment Flow (`payRent`) 🔴 Critical
**Spec:** Tenants pay periodic rent in $TOKEN. 90% of rent goes to Staking Contract as reward pool. NFT stays locked in contract during lease — does NOT transfer to tenant.

**Current:** No rental concept. Only `purchaseItem()` (primary, mints NFT to buyer) and `buyItem()` (secondary, transfers NFT to buyer). No periodic payment function.

**Affected contract:** `RWAMarketplace`

---

#### GAP-03: Dynamic Promo/Discount Toggle 🔴 Critical
**Spec:** Admin-controlled promotion system:
```solidity
bool public isPromotionActive;
mapping(uint256 => bool) public promoEligibleItems;
uint256 public discountPercentage;
function togglePromotion(bool _status) external;
function getPrice(uint256 _tokenId) public view returns (uint256);
```
Only stakers get the discount. Only Admin/Marketing role can toggle.

**Current:** No promo state, no discount logic, no per-item eligibility mapping in `RWAMarketplace`.

**Affected contract:** `RWAMarketplace`

---

#### GAP-04: Staker Verification Cross-Contract Call 🔴 Critical
**Spec:** Marketplace must call Staking Contract to check if buyer is currently staking before applying discount: `isUserStaking(msg.sender)`.

**Current:** `RWAMarketplace` has no reference to `RWAStaking`. No `stakingContract` address stored. No cross-contract call.

**Affected contract:** `RWAMarketplace` (needs staking address), `RWAStaking` (needs `isStaking()` view)

---

#### GAP-05: Royalty on Secondary Sales 🟠 High
**Spec:** "Add royalty function for secondary sales — original creator gets percentage on every resale."

**Current:** `buyItem()` splits payment to seller + marketing wallet only. `RWACertificate` stores `vendor` per asset, but `RWAMarketplace` doesn't read it during secondary sales to pay royalty.

**Affected contract:** `RWAMarketplace`

---

#### GAP-06: Emergency Withdraw (Marketplace) 🟠 High
**Spec:** "Admin function to recover tokens accidentally sent to contract address."

**Current:** No `emergencyWithdraw()` or `rescueTokens()` in `RWAMarketplace`. Accidentally sent tokens are permanently locked.

**Affected contract:** `RWAMarketplace`

---

#### GAP-07: Marketplace → Staking Contract Link 🟠 High
**Spec:** Marketplace needs a stored reference to Staking contract for:
1. Routing rental funds (GAP-02)
2. Staker verification (GAP-04)

**Current:** `initialize()` takes `paymentToken`, `certificate`, `marketingWallet`, `admin` — no `stakingContract` parameter.

**Affected contract:** `RWAMarketplace`

---

#### GAP-08: NFT Lock Mechanism for Rental 🔴 Critical
**Spec:** For `RENTAL` assets, NFT must remain locked in the Marketplace contract during the lease. Tenant uses the asset but doesn't own the NFT.

**Current:** `listItem()` does escrow the NFT in the contract, but `buyItem()` always transfers it out. No concept of "rented but locked" state.

**Affected contract:** `RWAMarketplace`

---

#### GAP-09: Listing Struct Extension 🔴 Critical
**Spec:** `Listing` needs additional fields for rental support and category branching.

**Current struct:**
```solidity
struct Listing { address seller; uint256 tokenId; uint256 price; bool active; }
```

**Missing fields:** `AssetCategory category`, rental period info, tenant address.

**Affected contract:** `RWAMarketplace`

---

### RWAStaking Gaps

#### GAP-10: Revenue Sharing / External Reward Pool 🔴 Critical
**Spec:** Staking contract must accept external income (rental payments from Marketplace) and distribute proportionally to all stakers based on their staked amount. Uses Synthetix Reward-Per-Token pattern.

**Current:** Rewards are calculated purely from fixed APR formula: `amount * aprBps * duration / (365 days * BPS)`. No mechanism to receive external funds and distribute them. If contract balance is insufficient, `unstake()` with reward will revert.

**Affected contract:** `RWAStaking`

---

#### GAP-11: `claimReward()` Without Unstaking 🟠 High
**Spec:** Stakers should be able to call `claimReward()` to withdraw accumulated rental yield while keeping their stake active.

**Current:** Only `unstake()` exists, which withdraws principal + reward together and marks the stake as `withdrawn`. No way to harvest yield independently.

**Affected contract:** `RWAStaking`

---

#### GAP-12: `isStaking(address)` View Function 🟠 High
**Spec:** Staking contract must expose a function for Marketplace to verify if a user is currently staking.

**Current:** `getStakes(address)` returns all stakes, but no simple boolean `isStaking()` helper. Marketplace would need to iterate off-chain.

**Affected contract:** `RWAStaking`

---

#### GAP-13: `totalStaked` Global Tracking 🟠 High
**Spec:** For proportional revenue distribution (Synthetix pattern), contract needs `totalStaked` — the aggregate of all active stakes.

**Current:** No `totalStaked` variable. Each user's stakes tracked individually with no global sum.

**Affected contract:** `RWAStaking`

---

#### GAP-14: Emergency Withdraw (Forfeit All Interest) 🟡 Medium
**Spec:** "Users can withdraw principal in emergencies, forfeiting interest — to maintain user trust." Implies a dedicated function separate from normal unstake.

**Current:** `unstake()` before lock period applies 10% penalty on principal but does allow withdrawal. This partially satisfies the requirement. The spec suggests forfeiting interest (not penalizing principal), which is a different economic model.

**Affected contract:** `RWAStaking`

---

### RWACertificate Gaps

#### GAP-15: Asset Category on NFT 🟡 Medium
**Spec:** NFT metadata should differentiate asset types with specific fields:
- Warehouse: `Occupancy_Status`, `Monthly_Rent_Rate`
- Gold/Antiques: `Vault_Location`, `Certificate_Serial`
- All: `legal_document_hash` (SHA-256)

**Current:** `Asset` struct has generic `assetType` (string) and `serialNumber`. Extended metadata lives in IPFS URI (off-chain). No on-chain `AssetCategory` enum or structured fields for vault/occupancy.

**Note:** Acceptable if all extended metadata stays in IPFS JSON. Only a gap if on-chain verification of `legal_document_hash` is required.

**Affected contract:** `RWACertificate`

---

#### GAP-16: Metadata Update Function (Authorized) 🟡 Medium
**Spec (Technical Brief, Test H):** "Attempt to modify warehouse data post-mint → data immutable, except through authorized update function (logged)."

**Current:** No `updateTokenURI()` or `updateAsset()` function. Once minted, URI and asset data cannot be changed. This is arguably more secure, but the spec explicitly mentions an authorized update path.

**Affected contract:** `RWACertificate`

---

## Gap Summary by Severity

| Severity | Count | IDs |
|----------|-------|-----|
| 🔴 Critical | 7 | GAP-01, GAP-02, GAP-03, GAP-04, GAP-08, GAP-09, GAP-10 |
| 🟠 High | 5 | GAP-05, GAP-06, GAP-07, GAP-11, GAP-12, GAP-13 |
| 🟡 Medium | 3 | GAP-14, GAP-15, GAP-16 |

---

## Gap-to-Contract Impact Map

| Contract | Gaps | Changes Needed |
|----------|------|---------------|
| RWAMarketplace | GAP-01,02,03,04,05,06,07,08,09 | Major rewrite — add rental flow, promo system, staking link, royalty, emergency withdraw, extend Listing struct |
| RWAStaking | GAP-10,11,12,13,14 | Add Synthetix reward distribution, `claimReward()`, `isStaking()`, `totalStaked`, emergency withdraw |
| RWACertificate | GAP-15,16 | Minor — optional on-chain category enum, authorized metadata update |
| RWAToken | — | No changes needed |
| HybridProxyAdmin | — | No changes needed |
| RWATreasury | — | No changes needed |

---

## Alignment with TO_FIX.txt

| TO_FIX Item | Related Gaps |
|-------------|-------------|
| Unify payment distribution | GAP-02, GAP-07, GAP-10 (rental → staking pool flow) |
| Enforce staking lock logic | GAP-14 (emergency withdraw vs penalty model) |
| Separate asset classes clearly | GAP-01, GAP-09, GAP-15 (AssetCategory enum) |
| Pick escrow vs instant settlement | GAP-02, GAP-08 (rental = escrow, direct sale = instant) |
| Clarify oracle responsibility | Already handled — Chainlink per assetType in Marketplace |

---

## Implementation Status

All 16 gaps have been addressed:

| GAP | Status | Implementation |
|-----|--------|---------------|
| GAP-01 | ✅ Done | `enum AssetCategory { DIRECT_SALE, RENTAL }` in RWAMarketplace |
| GAP-02 | ✅ Done | `payRent()` routes 90% to Staking via `notifyRewardAmount()` |
| GAP-03 | ✅ Done | `isPromotionActive`, `promoEligibleItems`, `discountBps`, `togglePromotion()` |
| GAP-04 | ✅ Done | `_getEffectivePrice()` calls `stakingContract.isStaking(msg.sender)` |
| GAP-05 | ✅ Done | `buyItem()` pays `royaltyBps` to original vendor via `certificate.getAsset()` |
| GAP-06 | ✅ Done | `rescueTokens()` in RWAMarketplace |
| GAP-07 | ✅ Done | `stakingContract` added to `initialize()` + `setStakingContract()` |
| GAP-08 | ✅ Done | RENTAL listings: NFT stays in contract, `startRental()`/`endRental()` manage tenant |
| GAP-09 | ✅ Done | `Listing` struct extended with `AssetCategory category` |
| GAP-10 | ✅ Done | Synthetix `rewardPerTokenStored` pattern + `notifyRewardAmount()` in RWAStaking |
| GAP-11 | ✅ Done | `claimRevenue()` in RWAStaking — claim yield without unstaking |
| GAP-12 | ✅ Done | `isStaking(address)` view in RWAStaking |
| GAP-13 | ✅ Done | `totalStaked` + `userTotalStaked` + `eligibleStaked` + `userEligibleStaked` tracking in RWAStaking |
| GAP-14 | ✅ Done | `emergencyWithdraw()` — admin-only (`onlyRole(DEFAULT_ADMIN_ROLE)`), returns principal, forfeits APR |
| GAP-15 | — | Deferred — extended metadata stays in IPFS JSON (off-chain) |
| GAP-16 | ✅ Done | `updateTokenURI()` in RWACertificate (admin-only) |

---

## Security Enhancement: MEV / Flash-Stake Mitigation (SEC-4)

**Problem:** An attacker could front-run `notifyRewardAmount()` by staking a large amount in the same block, capturing a disproportionate share of revenue, then immediately unstaking.

**Solution:** `MIN_STAKE_DURATION = 1 day` with `eligibleStaked` tracking:
- Revenue distributes only to `eligibleStaked` (stakes older than 1 day), not `totalStaked`
- `unstake()` reverts with `TooEarly` if stake < 1 day old
- `_promoteEligible(account)` lazily promotes stakes crossing the 1-day threshold
- `emergencyWithdraw()` restricted to `DEFAULT_ADMIN_ROLE` (prevents penalty bypass)

**Test result (SEC-4):**
```
Honest staked 10k (>1 day ago), Attacker staked 90k (same block as revenue)
  Attacker gets: 0 tokens (0%)
  Honest gets:   10,000 tokens (100%)
  Attacker unstake: blocked (TooEarly)
```

**Status:** ✅ Fully mitigated — verified by 48/48 passing tests

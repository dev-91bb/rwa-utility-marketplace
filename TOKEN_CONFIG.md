# Token Configuration

## PropertyToken (ERC-1400)

Each property listing deploys one `PropertyToken` proxy via `PropertyFactory`. All parameters are set at deploy time and most are immutable after initialization.

### Supply

| Parameter | Set By | Mutable | Notes |
|---|---|---|---|
| `totalSupply_` | Admin at deploy | ❌ | Minted entirely to `tokenOwner_` at init |
| `maxSupply` | Derived from `totalSupply_` | ❌ | Hard cap — `_issueByPartition` reverts if exceeded |
| `issuable` | Starts `true` | ✅ (one-way) | Call `finalizeIssuance()` to permanently lock to current supply |

**No default supply.** Admin sets it per property via `PropertyFactory.deployProperty()`:

```
totalSupply = totalValueUSD / tokenPriceUSD
```

Example: $850,000 property at $50/token → 17,000 tokens minted, 17,000 max supply.

Once `finalizeIssuance()` is called, no more tokens can ever be minted. This should be called immediately after the initial distribution is complete.

---

### Pricing

| Parameter | Set By | Mutable | Notes |
|---|---|---|---|
| `tokenPriceUSD` | Admin at deploy | ❌ | Price per token in USD cents (e.g., `5000` = $50.00) |
| `totalValueUSD` | Admin at deploy | ❌ | Property valuation in USD cents |

Price is informational on-chain. Actual payment amounts are enforced by `RWAMarketplace` listings.

---

### Transfer Restrictions

| Parameter | Set By | Mutable | Notes |
|---|---|---|---|
| `kycRegistry` | Admin at deploy | ✅ via `setKYCRegistry()` | Shared across all properties |
| KYC tier required | KYCRegistry | ✅ | Checked on every transfer via `_update()` |
| Partition | Per token holder | ✅ via `moveByPartition()` | `unlocked` = transferable, `locked` = frozen |

---

### Partitions

| Partition | Value | Transferable | Use Case |
|---|---|---|---|
| `PARTITION_UNLOCKED` | `bytes32("unlocked")` | ✅ (KYC required) | Normal investor holdings |
| `PARTITION_LOCKED` | `bytes32("locked")` | ❌ | Vesting, lock-up periods, regulatory freeze |

Admin can move tokens between partitions via `moveByPartition(from, to, holder, amount)`.

---

## RWAToken (BEP-20)

Utility/payment token used across the marketplace.

| Parameter | Set By | Mutable | Notes |
|---|---|---|---|
| `initialSupply_` | Admin at deploy | — | Minted to owner at init |
| Max supply | None | — | **No hard cap.** Owner can `mint()` freely. |

> ⚠️ Consider adding a cap to `RWAToken` if it is used as an investment instrument. Currently uncapped — suitable only as a utility/payment token.

---

## Marketplace Fee Config

| Parameter | Default | Range | Setter |
|---|---|---|---|
| `saleSellerBps` | 9000 (90%) | Must sum to 10000 | `setSaleFeeBps()` |
| `saleAdminBps` | 1000 (10%) | Must sum to 10000 | `setSaleFeeBps()` |
| `rentalOwnerBps` | 7000 (70%) | Must sum to 10000 | `setRentalFeeBps()` |
| `rentalCompanyBps` | 2000 (20%) | Must sum to 10000 | `setRentalFeeBps()` |
| `rentalAdminBps` | 1000 (10%) | Must sum to 10000 | `setRentalFeeBps()` |
| `ESCROW_PERIOD` | 24 hours | Constant | Not configurable |
| `PRICE_FRESHNESS` | 6 hours | Constant | Not configurable |

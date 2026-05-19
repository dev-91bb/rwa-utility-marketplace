# Token Configuration

This document explains how tokens are configured across the platform — what can be set, what is fixed, and what the defaults are.

---

## PropertyToken (ERC-1400 Security Token)

Each property listing gets its own `PropertyToken` contract deployed via `PropertyFactory`. The token represents fractional ownership of that specific property.

### Token Supply

There is **no default supply**. The admin sets the supply manually when creating a listing, calculated as:

```
Total Tokens = Property Value (USD) ÷ Token Price (USD)

Example: $850,000 property ÷ $50 per token = 17,000 tokens
```

All tokens are minted to the admin wallet at deploy time. The admin then distributes them to investors through the marketplace.

**The supply is hard-capped at the amount set during deployment.** It can never be increased beyond that number. This protects investors — their ownership percentage cannot be diluted after they buy in.

| What | Value | Can Change? |
|---|---|---|
| Initial supply | Set by admin at deploy | No |
| Maximum supply (cap) | Same as initial supply | No |
| Can mint more? | Yes, until `finalizeIssuance()` is called | One-way lock |

> **Best practice:** Call `finalizeIssuance()` immediately after the initial token distribution is complete. This permanently prevents any new tokens from being minted, even by the admin.

---

### Token Price & Property Value

These are stored on-chain for transparency and reference, but the actual payment amounts are enforced by the marketplace when investors buy or sell.

| What | Example | Can Change? |
|---|---|---|
| Token price | $50 per token (stored as `5000` USD cents) | No |
| Property value | $850,000 (stored as `85000000` USD cents) | No |

---

### Transfer Restrictions (KYC)

Every token transfer — whether buying, selling, or moving between wallets — is checked against the KYC Registry. If either the sender or receiver is not verified, the transfer is blocked.

The KYC Registry is shared across all properties. An investor only needs to verify their identity once to be able to invest in any property on the platform.

| What | Can Change? | How |
|---|---|---|
| KYC Registry address | Yes | Admin calls `setKYCRegistry()` |
| Investor verification | Yes | KYC operator calls `verify(wallet)` or `revoke(wallet)` |

**Transfer failure reason codes** (ERC-1066 standard):

| Code | Meaning |
|---|---|
| `0x51` | Transfer allowed |
| `0x56` | Sender not KYC verified |
| `0x57` | Receiver not KYC verified |
| `0x54` | Contract is paused |
| `0x55` | Tokens are locked (in locked partition) |
| `0x52` | Insufficient balance |

---

### Partitions (Token Locking)

Each investor's tokens can be in one of two partitions:

| Partition | Meaning | Can Transfer? |
|---|---|---|
| `unlocked` | Normal holdings | Yes (KYC required) |
| `locked` | Frozen tokens | No |

The admin can move tokens between partitions using `moveByPartition()`. This is used for:
- **Vesting periods** — tokens locked until a date, then moved to unlocked
- **Regulatory freeze** — OJK or legal requirement to freeze a specific investor's tokens
- **Lock-up after primary sale** — prevent immediate resale after initial offering

---

## RWAToken (BEP-20 Utility Token)

This is the platform's payment token used to buy and sell assets in the marketplace.

| What | Value | Can Change? |
|---|---|---|
| Initial supply | Set by admin at deploy | — |
| Maximum supply | **None — no hard cap** | — |
| Can mint more? | Yes, owner can mint anytime | — |

> ⚠️ `RWAToken` has no supply cap because it is a utility/payment token, not an investment instrument. If this token is ever used as an investment vehicle, a cap should be added.

---

## Marketplace Fees

All fees are set in basis points (BPS), where 10,000 BPS = 100%.

### Property Token Sale & NFT Direct Sale

| Recipient | Default | Meaning |
|---|---|---|
| Seller | 9,000 BPS | 90% of the sale price |
| Admin wallet | 1,000 BPS | 10% platform fee |

Changed by admin via `setSaleFeeBps(sellerBps, adminBps)`. Both values must add up to exactly 10,000.

### Rental

| Recipient | Default | Meaning |
|---|---|---|
| Property owner | 7,000 BPS | 70% of the rental payment |
| Company wallet | 2,000 BPS | 20% management fee |
| Admin wallet | 1,000 BPS | 10% platform fee |

Changed by admin via `setRentalFeeBps(ownerBps, companyBps, adminBps)`. All three must add up to exactly 10,000.

### Escrow & Timing

| What | Value | Can Change? |
|---|---|---|
| Escrow hold period | 24 hours | No — hardcoded constant |
| Price freshness window | 6 hours | No — hardcoded constant |

All payments are held in escrow for 24 hours before the seller can claim them. This gives the admin time to freeze and dispute a transaction if needed. Listing prices must be updated at least every 6 hours to remain valid — this prevents stale prices from being exploited.

# RWA Utility Marketplace

A tokenized real-world asset platform built on BNB Chain. The platform allows investors to buy fractional ownership of real estate properties using blockchain tokens, earn rental yield, and trade their holdings on a secondary market — all with on-chain transparency and OJK-compliant KYC enforcement.

---

## How It Works

### For Investors

1. Complete KYC verification once. Your wallet is whitelisted on-chain and works across all properties.
2. Browse available properties and buy fractional tokens. Each token represents a share of the property.
3. Earn rental yield distributed proportionally to your token holdings.
4. Sell your tokens on the secondary market at any time through the marketplace.
5. Receive an NFT certificate as proof of your investment, which is updated when you sell.

### For Admins

1. Deploy a new `PropertyToken` contract per listing using `PropertyFactory`. Token supply and price are set at this point and cannot be changed.
2. The backend automatically detects the new listing from on-chain events.
3. Upload photos and description via the admin dashboard to publish the listing.
4. Approve KYC submissions to whitelist investor wallets.
5. Manage escrow disputes and platform settings.

---

## Architecture

The platform is split into two layers:

```
HybridProxyAdmin (Ownable2Step)
  │
  ├── Property Layer
  │     ├── PropertyToken × N  — one token contract per property listing
  │     ├── PropertyFactory    — deploys new PropertyToken proxies
  │     ├── PropertyRegistry   — tracks all deployed property contracts
  │     └── KYCRegistry        — shared investor whitelist
  │
  └── Marketplace Layer
        ├── RWAToken           — platform utility/payment token (BEP-20)
        ├── RWACertificate     — NFT proof of investment (BEP-721)
        ├── RWAMarketplace     — handles all buying, selling, and renting
        └── RWAStaking         — token staking with lock-up tiers (currently decoupled)
```

All contracts use the **Hybrid Proxy pattern**. The upgrade admin address is baked into each contract's bytecode at deploy time as an immutable value. This means even if someone front-runs the initialization transaction, they cannot take over upgrade authority — the proxy admin is fixed before the contract is ever deployed.

---

## Token Standards

| Contract | Standard | Purpose |
|---|---|---|
| `RWAToken` | BEP-20 (ERC-20) | Platform payment token. Used to buy/sell assets in the marketplace. Includes burn and gasless permit. |
| `PropertyToken` | ERC-1400 (Security Token) | Fractional property ownership. One contract per property. Enforces KYC on every transfer. Supports partition-based locking for vesting and regulatory freezes. |
| `RWACertificate` | BEP-721 (ERC-721) | NFT certificate issued to investors as proof of ownership. Burned when the investor sells their tokens, and a new one is minted for the buyer. |

> BEP-20 and BEP-721 are BNB Chain's equivalents of ERC-20 and ERC-721. ERC-1400 is the international security token standard — it adds transfer restriction hooks, partition-based balances, operator authorization, and standardized reason codes (ERC-1066) to explain why a transfer was blocked.

---

## Contracts

### Property Layer

**`PropertyToken`** — The core ownership token for each property. Built on ERC-1400, it enforces that only KYC-verified wallets can send or receive tokens. Tokens can be in an `unlocked` partition (freely tradeable) or a `locked` partition (frozen, used for vesting or regulatory holds). The total supply is fixed at deploy time and cannot be inflated.

**`PropertyFactory`** — When admin creates a new listing, this contract deploys a fresh `PropertyToken` proxy pointing to the shared implementation contract. All property tokens share the same logic but have completely separate state (balances, supply, metadata).

**`PropertyRegistry`** — Keeps a record of every deployed property token, mapping a human-readable property ID to its contract address. Also tracks listing status (Active, Delisted, Sold). The `getAllProxies()` function returns all addresses at once, which is used for batch upgrades.

**`KYCRegistry`** — A simple on-chain whitelist. When an investor completes identity verification off-chain, the admin calls `verify(walletAddress)`. That wallet can then transfer any PropertyToken on the platform. Verification can be revoked instantly if needed.

### Marketplace Layer

**`HybridProxyAdmin`** — The single authority that can upgrade any contract on the platform. Uses two-step ownership transfer to prevent accidents. The `batchUpgrade()` function upgrades all property token contracts at once by reading the full list from `PropertyRegistry`.

**`RWAToken`** — The platform's BEP-20 utility token. Used as the payment currency in the marketplace. Supports burning and EIP-2612 permit for gasless approvals.

**`RWACertificate`** — A BEP-721 NFT that serves as a human-readable proof of investment. Minted when an investor buys tokens (primary or secondary market). When the investor sells their tokens, their certificate is burned and a new one is minted for the buyer. Has a status lifecycle (Active → Redeemed → Fulfilled) for physical asset redemption use cases.

**`RWAMarketplace`** — The single entry point for all transactions. Handles:
- Primary sale of PropertyTokens (admin distributes initial supply)
- Secondary sale of PropertyTokens (investors resell their holdings)
- NFT asset listings (direct sale and rental)
- 24-hour escrow on all payments with admin dispute/freeze capability

**`RWAStaking`** — Allows token holders to stake `RWAToken` for yield. Supports four lock-up tiers (30/90/180/365 days) with different APR rates. Early unstake incurs a 10% penalty. Currently decoupled from the marketplace pending product decisions on revenue share weighting.

---

## Key Flows

### Buying Property Tokens (Primary Market)
```
1. Admin lists tokens via RWAMarketplace
2. Investor (KYC verified) calls buyPropertyTokens()
3. Payment held in escrow for 24 hours
4. PropertyTokens transferred to investor
5. RWACertificate minted as proof of investment
6. Seller claims 90% after 24h; admin claims 10%
```

### Selling Property Tokens (Secondary Market)
```
1. Investor calls listPropertyTokens() — tokens held in marketplace escrow
2. Buyer (KYC verified) calls buyPropertyTokens()
3. Payment held in escrow for 24 hours
4. PropertyTokens transferred to buyer
5. Seller's RWACertificate burned
6. New RWACertificate minted for buyer
7. Seller claims 90% after 24h; admin claims 10%
```

### Upgrading All Property Contracts
```solidity
address[] memory proxies = registry.getAllProxies();
proxyAdmin.batchUpgrade(proxies, newImplementation);
```
One transaction upgrades every property token contract on the platform simultaneously.

### Auto-Detecting New Listings (Backend)
```
PropertyFactory emits PropertyRegistered event
  → Backend picks up event
  → Creates DB record with status "pending_photos"
  → Admin dashboard shows "⚠️ Needs Photos" alert
  → Admin uploads photos + description
  → Listing goes live on the frontend
```

---

## On-Chain vs Off-Chain Data

The blockchain stores financial truth. Everything else lives in the backend database.

| Stored On-Chain | Stored Off-Chain (DB) |
|---|---|
| Token supply and price | Property photos |
| Ownership balances | Description and amenities |
| KYC verification status | Documents and legal files |
| Transfer history | Display status and labels |
| Fee splits and escrow | Occupancy rates and manager info |

---

## Payment Flows

**Property Token Sale / NFT Direct Sale**
```
Buyer pays 100% → held in escrow 24h → Seller receives 90%, Admin receives 10%
```

**Rental**
```
Tenant pays 100% upfront → held in escrow 24h → Owner 70%, Company 20%, Admin 10%
```

**Escrow Dispute**
```
Admin freezes escrow → investigates → resolveEscrow(recipient, amount) or unfreezeEscrow()
```

---

## NFT Certificate Lifecycle

| Status | Transferable | Burnable | When |
|---|---|---|---|
| Active | ✅ | ❌ | Normal state after purchase |
| Redeemed | ❌ | ❌ | Investor has requested physical redemption |
| Fulfilled | ❌ | ✅ | Asset has been physically delivered |
| Cancelled | ❌ | ✅ | Transaction was cancelled/refunded |
| Expired | ❌ | ❌ | Validity period ended |
| Disputed | ❌ | ❌ | Under admin review |

---

## Deployment Order

```
1.  Deploy HybridProxyAdmin(ownerAddress)
2.  Deploy KYCRegistry(ownerAddress)
3.  Deploy PropertyToken implementation contract (proxyAdminAddress)
4.  Deploy PropertyRegistry(ownerAddress)
5.  Deploy PropertyFactory(propertyTokenImpl, registryAddress, ownerAddress)
6.  Call PropertyRegistry.setFactory(factoryAddress)
7.  Deploy RWAToken implementation → deploy ERC1967Proxy → initialize
8.  Deploy RWACertificate implementation → deploy ERC1967Proxy → initialize
9.  Deploy RWAMarketplace implementation → deploy ERC1967Proxy → initialize
10. Grant MINTER_ROLE on RWACertificate to RWAMarketplace
11. Grant VENDOR_ROLE on RWAMarketplace to verified vendors
12. Set adminWallet and companyWallet on RWAMarketplace
```

---

## Security

| Feature | What It Protects Against |
|---|---|
| Immutable `_proxyAdmin` in constructor | Front-running / MEV attacks during deployment |
| `_disableInitializers()` in constructor | Re-initialization attacks on implementation contracts |
| `Ownable2Step` on ProxyAdmin and Registry | Accidental ownership transfer to wrong address |
| `ReentrancyGuard` on all token-moving functions | Reentrancy attacks |
| `Pausable` on all contracts | Emergency stop if a vulnerability is discovered |
| `AccessControl` with explicit roles | Unauthorized minting, vendor fraud |
| KYC check on every PropertyToken transfer | Unverified wallets receiving security tokens |
| ERC-1400 `canTransfer()` with reason codes | Clear audit trail for every blocked transfer |
| 24h escrow with admin freeze | Payment disputes and fraudulent listings |
| 6h price freshness requirement | Stale price exploitation |
| Self-buy prevention | Wash trading on secondary market |
| `maxSupply` hard cap on PropertyToken | Supply inflation / ownership dilution |

---

## Mock UI

Located in `ui/`. Open any file directly in a browser — no build step or server required.

| File | Description |
|---|---|
| `index.html` | Homepage with property listings grid, filter tabs, and stats bar |
| `property.html` | Property detail page with investment widget and yield calculator |
| `admin.html` | Admin dashboard with pending listings queue, KYC approvals, contract addresses, and batch upgrade button |

---

## Documentation

| File | Description |
|---|---|
| `TOKEN_CONFIG.md` | Detailed token supply, pricing, partition, and fee configuration reference |
| `GAP_ANALYSIS.md` | Spec compliance tracking — what is implemented vs deferred |
| `TO_BE_RESOLVED.md` | Product decisions log — resolved, deferred, and obsolete items |

---

## Dependencies

- OpenZeppelin Contracts v5.x
- OpenZeppelin Contracts Upgradeable v5.x
- Chainlink Price Feeds
- Foundry + forge-std

## License

MIT

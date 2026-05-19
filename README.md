# RWA Utility Marketplace

Tokenized real-world asset platform on BNB Chain. Supports fractional property ownership, NFT-based asset certificates, rental/sale marketplace, and staking.

## Architecture Overview

```
HybridProxyAdmin (Ownable2Step)
  │
  ├── Property Layer
  │     ├── PropertyToken × N  (one ERC1967Proxy per listing, shared implementation)
  │     ├── PropertyFactory    (deploys proxies, registers in registry)
  │     ├── PropertyRegistry   (propertyId → proxy, getAllProxies for batch upgrade)
  │     └── KYCRegistry        (shared whitelist, verified once → all properties)
  │
  └── Marketplace Layer
        ├── RWAToken           (BEP-20 utility token)
        ├── RWACertificate     (ERC-721 NFT ownership certificate)
        ├── RWAMarketplace     (sale + rental with 24h escrow)
        └── RWAStaking         (lock tiers, currently disabled in marketplace)
```

## Token Standards

| Contract | Standard | Notes |
|---|---|---|
| `RWAToken` | **BEP-20** (ERC-20) | Utility token with burn + permit. BNB Chain compatible. |
| `PropertyToken` | **ERC-1400** (Security Token) | Fractional ownership token per property. Partition-based locking, operator authorization, issuance/redemption hooks, KYC transfer restrictions via ERC-1066 reason codes. |
| `RWACertificate` | **BEP-721** (ERC-721) | NFT ownership certificate with URI storage and status lifecycle. |

> BEP-20 and BEP-721 are BNB Chain's equivalents of ERC-20 and ERC-721. ERC-1400 is the security token standard — PropertyToken implements the full interface including partitions (`unlocked` / `locked`), operator management, and `canTransfer()` with ERC-1066 reason codes.

---

All contracts use the **Hybrid Proxy pattern**: immutable `_proxyAdmin` baked into implementation bytecode at deploy time — immune to front-running/MEV attacks.

---

## Contracts

### Property Layer

| Contract | Description |
|---|---|
| `PropertyToken` | ERC-20 fractional ownership token per property. KYC transfer restrictions via shared registry. UUPS upgradeable. |
| `PropertyFactory` | Deploys `ERC1967Proxy(sharedImpl, initData)` per listing. All proxies share one implementation. |
| `PropertyRegistry` | Maps `propertyId → proxy address`. Tracks status (Active/Delisted/Sold). Exposes `getAllProxies()` for batch upgrade. |
| `KYCRegistry` | Shared whitelist. Investor verifies once, can invest in any property. Supports tier-based verification. |

### Marketplace Layer

| Contract | Description |
|---|---|
| `HybridProxyAdmin` | Shared upgrade authority. `upgrade()`, `upgradeAndCall()`, `batchUpgrade()`. |
| `RWAToken` | BEP-20 utility token with burn + permit. |
| `RWACertificate` | ERC-721 NFT with status lifecycle (Active → Redeemed → Fulfilled). Transfer restricted by status. |
| `RWAMarketplace` | Primary + secondary sale and rental. 24h escrow, dispute resolution, Chainlink price feeds. |
| `RWAStaking` | Lock tiers (30/90/180/365 days), per-second rewards, early unstake penalty. Currently decoupled from marketplace. |

---

## Property Tokenization Flow

```
1. Admin deploys PropertyToken implementation once (with HybridProxyAdmin address immutable)
2. Admin calls PropertyFactory.deployProperty() per listing
   → deploys ERC1967Proxy pointing to shared implementation
   → registers proxy in PropertyRegistry
3. Backend detects PropertyRegistered event → creates DB record (status: pending_photos)
4. Admin uploads photos + description via dashboard → listing goes live
5. Investor completes KYC once → KYCRegistry.verify(wallet)
6. Investor buys PropertyTokens → transfer gated by KYC check
```

**Upgrade all properties at once:**
```solidity
address[] memory proxies = registry.getAllProxies();
proxyAdmin.batchUpgrade(proxies, newImplementation);
```

---

## Data Split

| On-chain (PropertyToken) | Off-chain (Backend DB) |
|---|---|
| Total supply | Photos |
| Token price | Description |
| Property value | Amenities |
| KYC restrictions | Documents |
| Transfer history | Status display |

---

## Marketplace Token Flow

**Sale (Primary & Secondary) — 90% seller / 10% admin:**
```
Buyer pays → escrow (24h) → Seller 90%, Admin 10%
```

**Rental — 70% owner / 20% company / 10% admin:**
```
Tenant pays → escrow (24h) → Owner 70%, Company 20%, Admin 10%
```

**Escrow dispute:**
```
Admin freezes → resolveEscrow(to, amount) or unfreezeEscrow()
```

---

## NFT Certificate Status

| Status | Can Transfer | Can Burn |
|---|---|---|
| Active | ✅ | ❌ |
| Redeemed | ❌ | ❌ |
| Fulfilled | ❌ | ✅ |
| Cancelled | ❌ | ✅ |
| Expired | ❌ | ❌ |
| Disputed | ❌ | ❌ |

---

## Deployment Order

```
1. Deploy HybridProxyAdmin(owner)
2. Deploy KYCRegistry(owner)
3. Deploy PropertyToken implementation (proxyAdmin address)
4. Deploy PropertyRegistry(owner) → setFactory(factoryAddress)
5. Deploy PropertyFactory(implementation, registry, owner)
6. Deploy RWAToken, RWACertificate, RWAMarketplace implementations
7. Deploy ERC1967Proxy for each with initialize calldata
8. Configure roles:
   - Grant MINTER_ROLE to Marketplace on Certificate
   - Grant VENDOR_ROLE to verified vendors
   - Set price feeds, fee wallets, redemption fees
```

---

## Security

- Hybrid Proxy: immutable `_proxyAdmin` in constructor, `_disableInitializers()` — front-run safe
- `Ownable2Step` on ProxyAdmin and Registry — two-step ownership transfer
- `ReentrancyGuard` on all token-moving functions
- `Pausable` emergency stop on all contracts
- `AccessControl` for role-based permissions (MINTER, VENDOR, OPERATOR)
- Chainlink oracle with 6h staleness check
- 24h escrow with admin freeze/dispute capability
- KYC transfer restrictions on all PropertyToken transfers
- Self-buy prevention on secondary market

---

## Mock UI

Located in `ui/`. Open directly in browser — no build step.

| File | Description |
|---|---|
| `index.html` | Property listings with filter tabs |
| `property.html` | Property detail + invest widget with yield calculator |
| `admin.html` | Admin dashboard: pending completion queue, KYC queue, contracts, batch upgrade |

---

## Dependencies

- OpenZeppelin Contracts v5.x
- OpenZeppelin Contracts Upgradeable v5.x
- Chainlink Price Feeds
- Foundry (forge-std)

## License

MIT

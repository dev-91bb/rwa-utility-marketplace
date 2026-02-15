# RWA Utility Marketplace

Tokenized real-world asset marketplace on Binance Smart Chain (BSC).

## Contracts

| Contract         | Description                                      |
|------------------|--------------------------------------------------|
| HybridProxyAdmin | Shared upgrade authority for all UUPS proxies   |
| RWAToken         | BEP-20 utility token with burn + permit          |
| RWAStaking       | Staking with 1/3/6/12 month tiers, per-second APR |
| RWACertificate   | ERC-721 NFT representing real-world asset ownership |
| RWAMarketplace   | Primary & secondary market with Chainlink oracles |
| RWATreasury      | Optional: Unified fee receiver with auto-distribution |

## Architecture

```
HybridProxyAdmin (single instance)
        │
        ├── RWAToken (Proxy)
        ├── RWAStaking (Proxy)
        ├── RWACertificate (Proxy)
        └── RWAMarketplace (Proxy)
```

All contracts use immutable `_proxyAdmin` set in constructor (MEV-protected).

## Token Flow

**Primary Market (5% fee):**
```
Buyer pays tokens → 95% Vendor, 5% Marketing → NFT minted to Buyer
```

**Secondary Market (3% fee):**
```
Buyer pays tokens → 97% Seller, 3% Marketing → NFT transferred to Buyer
```

**Staking:**
```
User stakes → Lock 1/3/6/12 months → Claim with APR reward
Early unstake → 10% penalty to Marketing
```

## NFT Certificate Status

| Status    | Description               | Can Transfer | Can Burn |
|-----------|---------------------------|--------------|----------|
| Active    | Tradeable                 | ✅           | ❌       |
| Redeemed  | Fee paid, awaiting pickup | ❌           | ❌       |
| Fulfilled | Asset delivered           | ❌           | ✅       |
| Cancelled | Refunded                  | ❌           | ✅       |
| Expired   | Validity ended            | ❌           | ❌       |
| Disputed  | Frozen                    | ❌           | ❌       |

## Redemption Flow

1. User calls `redeem(tokenId)` → pays redemption fee on-chain
2. User presents NFT proof to vendor
3. Vendor calls `markFulfilled(tokenId)`
4. Admin calls `burn(tokenId)` after asset handover

## Deployment Order

1. Deploy `HybridProxyAdmin(owner)`
2. Deploy implementations: RWAToken, RWAStaking, RWACertificate, RWAMarketplace
3. Deploy `ERC1967Proxy` for each with initialize calldata
4. Configure:
   - Grant `MINTER_ROLE` to Marketplace on Certificate
   - Grant `VENDOR_ROLE` to verified vendors
   - Set price feeds per asset type
   - Set redemption fees per asset type
   - Set staking APR rates

## Security Features

- Hybrid Proxy pattern (MEV/front-run protection)
- Ownable2Step for ProxyAdmin
- ReentrancyGuard on all token transfers
- Pausable for emergency stops
- AccessControl for role-based permissions
- Chainlink oracle with staleness check

## Dependencies

- OpenZeppelin Contracts v5.x
- OpenZeppelin Contracts Upgradeable v5.x
- Chainlink Price Feeds

## License

MIT

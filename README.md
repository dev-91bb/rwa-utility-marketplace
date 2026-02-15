# RWA Utility Marketplace

Tokenized real-world asset marketplace on Binance Smart Chain (BSC).

## Contracts

| Contract         | Description                                      |
|------------------|--------------------------------------------------|
| HybridProxyAdmin | Shared upgrade authority for all UUPS proxies   |
| RWAToken         | BEP-20 utility token with burn + permit          |
| RWAStaking       | Staking with 1/3/6/12 month tiers (currently disabled in marketplace) |
| RWACertificate   | ERC-721 NFT representing real-world asset ownership |
| RWAMarketplace   | Sale + rental with 24h escrow and dispute resolution |

## Architecture

```
HybridProxyAdmin (single instance)
        │
        ├── RWAToken (Proxy)
        ├── RWACertificate (Proxy)
        └── RWAMarketplace (Proxy)
```

All contracts use immutable `_proxyAdmin` set in constructor (MEV-protected).

## Token Flow

**Sale (Primary & Secondary) — 90% seller / 10% admin:**
```
Buyer pays tokens → 100% held in escrow (24h) → Seller claims 90%, Admin claims 10%
```

**Rental (Warehouse) — 70% owner / 20% company / 10% admin:**
```
Tenant pays rent → 100% held in escrow (24h) → Owner claims 70%, Company 20%, Admin 10%
```

**Escrow Dispute Flow:**
```
Admin freezes escrow within 24h → resolveEscrow(to, amount) or unfreezeEscrow()
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
2. Deploy implementations: RWAToken, RWACertificate, RWAMarketplace
3. Deploy `ERC1967Proxy` for each with initialize calldata
4. Configure:
   - Grant `MINTER_ROLE` to Marketplace on Certificate
   - Grant `VENDOR_ROLE` to verified vendors
   - Set price feeds per asset type
   - Set redemption fees per asset type
   - Set admin wallet and company wallet addresses

## Security Features

- Hybrid Proxy pattern (MEV/front-run protection)
- Ownable2Step for ProxyAdmin
- ReentrancyGuard on all token transfers
- Pausable for emergency stops
- AccessControl for role-based permissions
- Chainlink oracle with staleness check
- 24h escrow with admin dispute/freeze capability
- Self-buy prevention on secondary market

## Dependencies

- OpenZeppelin Contracts v5.x
- OpenZeppelin Contracts Upgradeable v5.x
- Chainlink Price Feeds

## License

MIT

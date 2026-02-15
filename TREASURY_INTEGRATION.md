# Treasury Integration Guide

## Overview

All contracts support seamless switching between single wallet and Treasury contract for fee collection.

## Architecture

```
┌─────────────────┐
│  RWAMarketplace │──► marketingWallet ──┐
└─────────────────┘                       │
                                          ├──► Single Wallet OR Treasury
┌─────────────────┐                       │
│   RWAStaking    │──► penaltyReceiver ──┤
└─────────────────┘                       │
                                          │
┌─────────────────┐                       │
│ RWACertificate  │──► feeReceiver ──────┘
└─────────────────┘
```

## Deployment Options

### Option 1: Single Wallet Mode (Simple)

```solidity
// Deploy contracts pointing to one wallet
marketplace.initialize(..., singleWallet, ...);
staking.initialize(..., singleWallet, ...);
certificate.initialize(..., singleWallet, ...);
```

**Pros:** Simple, no extra gas, manual control
**Cons:** Manual distribution needed

---

### Option 2: Treasury Mode (Auto-distribution)

```solidity
// 1. Deploy Treasury with splits
address[] memory recipients = [marketing, dev, burn];
uint256[] memory bps = [5000, 3000, 2000]; // 50%, 30%, 20%
treasury.initialize(owner, recipients, bps);

// 2. Point all contracts to Treasury
marketplace.initialize(..., address(treasury), ...);
staking.initialize(..., address(treasury), ...);
certificate.initialize(..., address(treasury), ...);

// 3. Distribute periodically
treasury.distribute(address(rwaToken));
```

**Pros:** Automated splits, transparent, on-chain
**Cons:** Extra gas for distribution

---

## Switching Between Modes

### From Single Wallet → Treasury

```solidity
// 1. Deploy Treasury
treasury.initialize(owner, recipients, bps);

// 2. Update fee receivers
marketplace.setMarketingWallet(address(treasury));
staking.setPenaltyReceiver(address(treasury));
certificate.setFeeReceiver(address(treasury));
```

### From Treasury → Single Wallet

```solidity
// 1. Distribute remaining funds
treasury.distribute(address(rwaToken));

// 2. Update fee receivers
marketplace.setMarketingWallet(newWallet);
staking.setPenaltyReceiver(newWallet);
certificate.setFeeReceiver(newWallet);
```

---

## Treasury Configuration Examples

### Example 1: Marketing Focus
```solidity
recipients = [marketing, dev, burn];
bps = [7000, 2000, 1000]; // 70% marketing, 20% dev, 10% burn
```

### Example 2: Balanced
```solidity
recipients = [marketing, dev, staking_rewards, burn];
bps = [4000, 3000, 2000, 1000]; // 40/30/20/10
```

### Example 3: Simple Split
```solidity
recipients = [marketing, operations];
bps = [6000, 4000]; // 60/40
```

---

## Admin Functions

| Contract | Function | Purpose |
|----------|----------|---------|
| RWAMarketplace | `setMarketingWallet(address)` | Update fee receiver |
| RWAStaking | `setPenaltyReceiver(address)` | Update penalty receiver |
| RWACertificate | `setFeeReceiver(address)` | Update redemption fee receiver |
| RWATreasury | `setSplits(address[], uint256[])` | Update distribution splits |
| RWATreasury | `distribute(address)` | Trigger distribution |

---

## Gas Considerations

| Mode | Per Transaction | Distribution |
|------|----------------|--------------|
| Single Wallet | ~21k gas | Manual (0 gas) |
| Treasury | ~21k gas | ~50k gas per distribute() |

**Recommendation:** Use Treasury if distributing weekly/monthly. Use single wallet if distributing manually or less frequently.

---

## Security Notes

- Treasury splits must total 10000 BPS (100%)
- All recipients must be non-zero addresses
- Only owner can update splits
- Distribution is pull-based (call `distribute()`)
- Contracts don't need to know if receiver is wallet or Treasury

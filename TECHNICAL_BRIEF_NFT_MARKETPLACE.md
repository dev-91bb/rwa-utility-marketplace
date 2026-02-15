# Technical Brief: RWA NFT Marketplace & Staking Ecosystem (BEP-20)

> Building an NFT marketplace ecosystem based on Real World Assets (Industrial Warehouses) on Binance Smart Chain (BSC). System integrates asset ownership, rental revenue distribution via Staking, and dynamic promo features.

---

## 1. Smart Contract Architecture ("Quad-Core" System)

4 integrated contracts to deploy:

| Contract | Standard | Utility | Key Features |
|----------|----------|---------|-------------|
| **A: $TOKEN** | BEP-20 | Primary currency for rent & purchase | IBEP-20 with `permit` for gas efficiency |
| **B: WAREHOUSE NFT** | BEP-721 | Digital representation of warehouse units | IPFS metadata with SHA-256 legal document hash |
| **C: STAKING & REVENUE SHARE** | Custom | Holds rental yield, distributes to stakers proportionally | `claimReward()`, staker verification for discounts |
| **D: MARKETPLACE ENGINE** | Custom | Buy/sell and rental logic | Dynamic Promo Toggle (On/Off), Staker-Based Discount |

---

## 2. Master Flow: Logic & Interaction

1. **Minting Asset**: Admin mints NFT with full metadata (Location, Area, Document Hash)
2. **Staking for Revenue**: User locks $TOKEN to earn share of warehouse operational profits
3. **Rental Payment**: Tenant pays rent in $TOKEN → funds auto-routed to Contract C (Staking) as Reward Pool
4. **Dynamic Discount Logic**:
   - Admin activates `isPromoActive = true`
   - System checks: `if (user.isStaking && isPromoActive && item.isEligible)`
   - If qualified → contract applies price discount automatically (atomic)

---

## 3. Database & Metadata Specs (Off-Chain)

- **IPFS Storage**: All unit images and legal contract PDFs stored on IPFS (via Pinata/Web3.Storage)
- **Metadata Format**:
  ```json
  {
    "attributes": [
      {"trait_type": "Area", "value": "500m2"},
      {"trait_type": "Legal_Hash", "value": "0x..."},
      {"trait_type": "Monthly_Yield", "value": "12%"}
    ]
  }
  ```
- **Backend Indexing**: Use The Graph (Subgraph) for real-time blockchain data indexing on user dashboard

---

## 4. Key Security Requirements (Mandatory)

1. **Reentrancy Guard**: All `withdraw` and `buy` functions must use `nonReentrant` modifier
2. **Access Control**: Use `Ownable2Step` or `AccessControl` (OpenZeppelin) for sensitive functions (e.g., changing discount status)
3. **Emergency Stop**: Implement `Pause` function for contract anomalies

---

## 5. Development Milestones

| Sprint | Deliverable |
|--------|------------|
| Sprint 1 | Smart Contract Development (Token, NFT, Staking) |
| Sprint 2 | Marketplace Logic & Promo Toggle Integration |
| Sprint 3 | IPFS Metadata & Backend Indexing (The Graph) |
| Sprint 4 | Frontend Development (Next.js) & Wallet Integration |
| Sprint 5 | Security Audit & BSC Testnet Launch |

---

## 6. Test Scenarios

### Module 1: Staking (Revenue Sharing)

| ID | Scenario | Expected Result |
|----|----------|----------------|
| A | User stakes 1,000 $TOKEN | System records staking start time correctly |
| B | Admin deposits 10,000 $TOKEN rental income to contract | Staker receives proportional share based on ownership % |
| C | User attempts unstake before lock period ends | System applies penalty or rejects per configured rules |

### Module 2: Marketplace & Dynamic Discount

| ID | Scenario | Expected Result |
|----|----------|----------------|
| D | Promo OFF → staking user buys/rents | Normal price (no discount) |
| E | Promo ON → non-staking user buys | Normal price (no discount) |
| F | Promo ON → staking user buys | Price reduced by discount % automatically on-chain |

### Module 3: Asset Integrity (RWA Metadata)

| ID | Scenario | Expected Result |
|----|----------|----------------|
| G | Click NFT metadata link | JSON opens showing Legal Document Hash matching original PDF |
| H | Attempt to modify warehouse data post-mint | Blockchain data immutable — only authorized update function (logged) |

---

## 7. Test Checklist (Definition of Done)

All must be PASSED before Mainnet launch:

| ID | Function Description | Status | Dev Notes |
|----|---------------------|--------|-----------|
| TC-01 | Buy NFT using $TOKEN BEP-20 | | |
| TC-02 | Auto-distribute rental profit to stakers | | |
| TC-03 | Admin ON/OFF discount switch | | |
| TC-04 | Non-admin cannot access Promo functions | | |
| TC-05 | IPFS metadata syncs with Marketplace UI | | |

---

## 8. UAT Report Template

### Part 1: Token & Staking (The Economy)

| No | Feature | Demo Instruction | Result |
|----|---------|-----------------|--------|
| 1.1 | Staking Deposit | User locks 500 $TOKEN → wallet balance decreases, staking dashboard increases | |
| 1.2 | Revenue Inflow | Admin sends 1,000 $TOKEN (rental profit) to contract → all stakers' "Claimable Reward" increases | |
| 1.3 | Reward Claim | User clicks "Claim" → tokens enter wallet, "Claimable" resets to zero | |

### Part 2: Marketplace & NFT (The Assets)

| No | Feature | Demo Instruction | Result |
|----|---------|-----------------|--------|
| 2.1 | NFT Minting | Mint new unit → check BscScan: IPFS link with legal contract PDF visible | |
| 2.2 | Purchase/Rent | User buys unit → NFT transfers on-chain, payment auto-sent to seller/pool | |

### Part 3: Discount & Admin Control (The Promo)

| No | Feature | Demo Instruction | Result |
|----|---------|-----------------|--------|
| 3.1 | Promo Activation | Admin sets Promo ON → Marketplace prices show strikethrough for eligible items | |
| 3.2 | Staker Verification | User A (staker) gets discount price. User B (non-staker) sees normal price even with Promo ON | |
| 3.3 | Promo Deactivation | Admin sets Promo OFF → prices immediately return to normal for all users | |

### Part 4: Security & Access Control

| No | Feature | Demo Instruction | Result |
|----|---------|-----------------|--------|
| 4.1 | Admin-Only Lock | Non-admin tries "Open Promo" → system rejects (Transaction Reverted) | |
| 4.2 | Emergency Pause | Admin presses "Pause" → all marketplace transactions halt for fund safety | |

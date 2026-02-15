# Master Technical Flow — BEP-20 Network

## 1. Core Architecture Components

4 pillars on BSC:

| Contract | Standard | Primary Role | Interacts With |
|----------|----------|-------------|----------------|
| Token Contract | BEP-20 | Currency & exchange medium | All contracts |
| NFT Contract | BEP-721 | Digital asset (collection) | Marketplace |
| Marketplace | Custom Logic | Buy/sell & auction | Token, NFT, Staking |
| Staking Contract | Custom Logic | Reward & user loyalty | Token, Marketplace |

## 2. Contract Interaction Flow

### Listing Phase
1. Seller approves BEP-721 contract to grant Marketplace access
2. Seller calls `listNFT` on Marketplace (NFT ID + price in $TOKEN)

### Purchase Phase (Atomic)
When buyer clicks "Buy", 3 automatic interactions in one transaction:
1. Marketplace calls BEP-20: takes $TOKEN from buyer via `transferFrom`
2. Marketplace splits funds: fee to admin + remainder to seller
3. Marketplace calls BEP-721: sends NFT from seller to buyer via `safeTransferFrom`

## 3. Technical Specifications

### A. BEP-20 (Custom Token)
- Must follow IBEP20 interface
- Implement `Ownable` for access control (minting/burning)
- Compatible with Trust Wallet and MetaMask

### B. BEP-721 (NFT)
- Metadata stored on IPFS (decentralized)
- Royalty function for secondary sales (original creator gets percentage on resale)

### C. Marketplace (The Bridge)
- **Atomic Transaction**: NFT purchase + BEP-20 transfer must occur in one function. If either fails, entire transaction reverts (fraud prevention)
- **Emergency Withdraw**: Admin function to recover tokens accidentally sent to contract

## 4. Staking Integration

### Role in Ecosystem
Staking acts as an "Internal Bank". Users lock BEP-20 tokens for rewards:
- Interest in $TOKEN
- Whitelist access for rare NFTs
- Transaction fee discount on marketplace
- Revenue sharing instrument

### A. Deposit Flow (Locking)
1. User approves BEP-20 to Staking Contract
2. User calls `stake(amount)`
3. Contract records duration and amount, calculates reward per second/block

### B. Staking ↔ Marketplace Synergy
1. Marketplace checks Staking Contract: "Is this user staking?"
2. If yes → auto discount on admin fee OR purchase priority on certain NFT collections (optional)
3. If yes → auto revenue share based on staking package

### Staking Technical Requirements
- **Standard**: Use Reward-Per-Token pattern (Synthetix style) for accurate interest calculation across thousands of users
- **Lock-up Period**: Duration options (30, 90, 180 days) with different APY rates
- **Emergency Withdraw**: Users can withdraw principal in emergencies (forfeiting interest)
- **Reward Pool**: Define reward source — new minting OR marketplace transaction tax
- **Penalty**: Required function for early unstaking before lock period ends

---

## 5. Industrial Property Tokenization (Warehouse Edition)

NFT represents lease rights or ownership of physical warehouses. Staking functions as revenue sharing instrument.

### Architecture
- **BEP-721 (Warehouse NFT)**: Represents specific warehouse unit. Metadata includes area, location, legal documents
- **Staking Contract (Revenue Share)**: Users lock tokens to receive share of warehouse rental income
- **Marketplace Contract**: Buy/sell warehouse NFTs with Dynamic Discount

### Revenue Sharing Mechanism
1. Tenant pays warehouse rent in $TOKEN to Marketplace/Rental Contract
2. Rental funds automatically sent to Staking Contract
3. Staking Contract distributes funds proportionally to all stakers based on locked token amount

### Dynamic Discount (Switchable)
Admin-controlled toggle switch in Smart Contract:

```solidity
bool public isPromotionActive;
mapping(uint256 => bool) public promoEligibleItems;

function togglePromotion(bool _status) external onlyOwner {
    isPromotionActive = _status;
}

function getPrice(uint256 _tokenId) public view returns (uint256) {
    uint256 basePrice = listings[_tokenId].price;
    if (isPromotionActive && promoEligibleItems[_tokenId] && isUserStaking(msg.sender)) {
        return basePrice - (basePrice * discountPercentage / 100);
    }
    return basePrice;
}
```

### Technical Instructions
1. **Staking for Profit**: Profit from warehouse rental (not token inflation) enters Staking Pool as reward
2. **Toggleable Discount**: Boolean function to enable/disable discount globally or per NFT unit
3. **Staker Verification**: Marketplace must cross-contract call Staking to verify user staking status before applying discount
4. **Role Access**: Only Admin/Marketing wallet can open/close promo discount periods

### End-to-End Workflow

| Action | Actor | Contract | Impact |
|--------|-------|----------|--------|
| Rent Warehouse | Tenant | Marketplace | $TOKEN paid to Pool |
| Distribute Profit | System | Staking | Stakers receive rental yield |
| Open Promo | Admin | Marketplace | Discount active for selected items |
| Buy/Rent Unit | Staker | Marketplace | Gets discounted price (if promo ON) |

---

## 6. NFT Metadata Structure (JSON on IPFS)

```json
{
  "name": "Industrial Warehouse Block A-12",
  "description": "Lease ownership of 500m2 warehouse in Jababeka Industrial Zone.",
  "image": "ipfs://hash-warehouse-front-image",
  "external_url": "https://marketplace.com/units/a-12",
  "attributes": [
    { "trait_type": "Location", "value": "Cikarang, Bekasi" },
    { "trait_type": "Land Area", "value": "500 m2" },
    { "trait_type": "Power Capacity", "value": "22,000 VA" },
    { "trait_type": "Certificate", "value": "HGB (Building Rights)" },
    { "trait_type": "Lease Status", "value": "Active" },
    { "trait_type": "Monthly Profit Share", "value": "10%" }
  ],
  "properties": {
    "legal_document_hash": "SHA-256-hash-of-original-contract-pdf",
    "last_inspection_date": "2026-01-10"
  }
}
```

## 7. Off-Chain Database Schema

### Table: Units (Warehouses)

| Column | Type | Description |
|--------|------|-------------|
| nft_id | Integer (PK) | Token ID on blockchain |
| physical_address | Text | Real-world warehouse address |
| base_price | Decimal | Base price in $TOKEN |
| is_promo_active | Boolean | Toggle: true if discounted |
| promo_discount | Integer | Discount percentage (e.g., 10 = 10%) |

### Table: Staking_Analytics

| Column | Type | Description |
|--------|------|-------------|
| user_wallet | String | User wallet address |
| total_staked | Decimal | Amount of locked tokens |
| earned_revenue | Decimal | Total claimed warehouse rental profit |

### Discount Switch Logic
- **Trigger**: When admin changes `is_promo_active` in dashboard → calls Smart Contract to activate discount
- **Verification**: Frontend checks user staking status. If `is_staker == true` AND `is_promo_active == true` → UI shows discounted price

### IT Checklist
1. **IPFS Gateway**: Use Pinata/Infura for fast access to images and legal PDFs
2. **Indexing (The Graph)**: Use subgraph for real-time blockchain data on dashboard
3. **Document Hashing**: Every legal PDF scanned → SHA-256 hash → stored in NFT metadata (tamper-proof)

---

## 8. Multi-Asset Type Support (Rental vs Sale)

### Asset Category: Productive (Warehouse, Rental Property)
- Staking role: Stakers are "shareholders"
- Fund flow: Tenant pays rent → Staking Contract → Distributed to stakers
- Suitable for: Warehouses, rental apartments, heavy equipment

### Asset Category: Store of Value (Gold, Antiques, Residential)
- Problem: Gold/antiques sit in vault — no rental income to pay stakers
- Solution: Staking becomes **Loyalty Program / Value Guard**:
  - **Discount**: Stakers get discount when buying gold/antiques
  - **Buyback**: Company uses marketplace profits to buy back tokens and distribute to stakers

### Architecture Changes for Multi-Asset

Add `AssetType` identifier to Smart Contract:

#### A. Gold & Antiques (Vault System)
- Add Physical Verification Hash
- Metadata must link to: authenticity certificate (e.g., Antam/GIA) + physical vault location

#### B. Residential (Sale vs Rent)
- If sold (not rented): rental staking flow doesn't apply
- Staking as Down Payment: Users staking certain amount get priority access or lower installment rates

### Asset Type Enum (Multi-Purpose)

| Type | Description | Staking Role |
|------|-------------|-------------|
| `TYPE_RENTAL` | Warehouse / Rental Property | Revenue Share from tenants |
| `TYPE_COMMODITY` | Gold / Antiques | Purchase discount (not revenue share) |
| `TYPE_SALES` | Residential for Sale | Exclusive whitelist access |

### Feature Compatibility Table

| Asset | Primary Mechanism | Staking Role |
|-------|------------------|-------------|
| Warehouse | Monthly Rent | Receives tenant revenue share |
| Gold | Buy/Sell / Store | Admin fee & vault storage discount |
| Residential | Rent or Sell | Revenue share (rent) or price discount (buy) |
| Antiques | Auction / Collection | VIP access to exclusive auctions |

---

## 9. Modular Logic Implementation

### Logic Switch: Execution Path Differences

Add `AssetType` variable to `Listing` struct in Marketplace:
- **Type 0 (Rental/Yield)**: NFT locked in contract, tenant pays periodically, funds go to Staking Pool
- **Type 1 (Direct Sale)**: NFT transfers permanently, funds go directly to seller, staking only provides checkout discount

### Technical Instructions

1. **Enum AssetType**: Create `enum AssetCategory { RENTAL, DIRECT_SALE }`
2. **Revenue Share Mapping**:
   - `RENTAL` → `payRent()` sends 90% to Staking Contract for distribution
   - `DIRECT_SALE` → `buyItem()` sends funds directly to seller (minus admin fee)
3. **Staking Benefit Logic**:
   - `RENTAL` → Stakers receive passive income (yield)
   - `DIRECT_SALE` → Check `isStaking(user)`, if true apply `discountPercentage`
4. **Metadata Differentiation**:
   - Gold: `Vault_Location`, `Certificate_Serial`
   - Warehouse: `Occupancy_Status`, `Monthly_Rent_Rate`

### Contract Parameter Table

| Parameter | RENTAL (Warehouse) | DIRECT_SALE (Gold/Antiques) |
|-----------|-------------------|---------------------------|
| Ownership | Fractional / Lease Rights | Full Ownership (Transferable) |
| Staking Function | Profit Distribution (Yield) | Discount Activation (Promo) |
| Fund Trigger | Periodic Rental Payment | One-time Buy/Sell Transaction |
| Asset Status | Locked in Contract during lease | Transfers to Buyer wallet |

### QA Test Scenarios
- **Test 1 (Gold)**: Buy gold for 100 $TOKEN → funds go directly to seller → buyer gets 5% staker discount → NO revenue share to other stakers
- **Test 2 (Warehouse)**: Tenant pays 100 $TOKEN rent → funds go to Staking Contract → staker "Claimable" balance increases → NFT does NOT transfer to tenant

### Scalability Note
> System must handle thousands of listings with dynamic category filters. Marketplace Contract architecture must support adding new Asset Classes in the future without major code refactoring.

# Smart Contract Development Instructions (BSC)

**Project:** Utility Marketplace for Luxury & Industrial Assets  
**Network:** Binance Smart Chain (BSC) – Mainnet  
**Architecture:** Modular smart contracts (separate but integrated) using Solidity ^0.8.20

---

## 1. Core Contract Specifications

### A. Utility Token Contract (BEP-20)
- **Function:** Standard utility token.
- **Special Feature:** Burn function for future deflationary mechanisms.

### B. Staking Contract (ROI Pool)
- **Reward Logic:** Rewards calculated based on `block.timestamp`.
- **Early Withdrawal:** 10% penalty if unstaked before maturity.
- **Fee Redirect:** 10% penalty is automatically sent to `Marketing_Wallet_Address`.

### C. NFT Certificate Contract (ERC-721)
- **Minting:** Only callable by the Marketplace contract.
- **Metadata:** Stores IPFS URI containing asset details (asset type, vendor, serial number).
- **Status Mapping:** `bool isRedeemed` to indicate whether the physical asset has been claimed.

---

## 2. Marketplace Logic Flow

### A. `purchaseItem` (Primary Market)
1. **Price Feed:** Integrate Chainlink Aggregator to fetch real-time asset price in tokens.
2. **Payment Splitting:**
   - Transfer `totalPrice` from buyer via `transferFrom`.
   - 95% sent to `vendorAddress`.
   - 5% sent to `marketingWallet`.
3. **NFT Issuance:** Call `mintCertificate` to deliver proof of ownership to buyer.

### B. `resellItem` (Secondary P2P Market)
1. **Escrow:** NFT is transferred to the Marketplace contract during listing.
2. **Trade Execution:**
   - 97% of payment to seller.
   - 3% royalty fee to `marketingWallet`.
3. **Transfer:** NFT is transferred from Marketplace to the new buyer.

### C. `buyBackGold` (Liquidity Pool)
1. **Oracle Check:** Fetch current gold market price.
2. **Spread:** Apply buy-back price (e.g., 95% of oracle price).
3. **Execution:**
   - User returns NFT to contract.
   - Contract sends tokens from `Liquidity_Pool_Address` to user.

---

## 3. Security & Access Control
- **Ownable / AccessControl (OpenZeppelin):**
  - `ADMIN_ROLE`: Core team
  - `VENDOR_ROLE`: Verified partners
- **ReentrancyGuard:** Use `nonReentrant` for all fund/token transfer functions.
- **Pausable:** Emergency stop for suspicious activity.

---

## 4. IT Deliverables Checklist
- Deploy contracts to BSC Testnet.
- Provide ABI documentation for frontend integration.
- Test Price Oracle accuracy for gold/property conversion.
- Gas fee simulation and reporting.

---

## 5. Marketplace Transaction Cycle
- **Vendor Integration:** Vendors list products priced in fiat (USD/IDR), auto-converted to tokens.
- **Purchase & Lock:** Tokens sent to Marketplace contract.
- **Settlement:**
  - Partial swap to stablecoins via DEX (e.g., PancakeSwap) if vendors require fiat.
  - Partial burn or fee allocation to marketing/development wallet.
- **Verification:** NFT certificate issued as proof of claim.

---

## 6. Staking Flow (Incentives)

- **Stake Duration Tiers:** Fixed lock periods of **1, 3, 6, 9, and 12 months**.
- **Reward Mechanism:** Rewards are calculated based on `block.timestamp` and vest only after the selected lock period ends.
- **ROI Rates:** Reward rates are **configurable and may be updated in the future** by governance/admin, without changing lock durations.
- **Utility Benefits:** Long-term stakers may receive priority access and special discounts within the marketplace.
- **Unstaking Policy:**
  - Early unstake before maturity incurs a **10% penalty**.
  - Penalty funds are redirected to the **Marketing / Treasury Wallet** (or designated protocol account).

---

## 7. Secure & Transparent Contract Architecture
- **Access Control:** Role-based vendor management.
- **Price Oracle:** Chainlink/Band Protocol for accurate global pricing.
- **Emergency Stop:** Pause all transactions if vulnerabilities are found.
- **Transparency Dashboard:** Public visibility of staking and escrow balances on BSCScan.

---

## 8. Token Distribution Model (Example)
- User buys asset using tokens.
- Distribution per transaction:
  - 95% → Vendor
  - 3% → Staking Pool (ROI source)
  - 2% → Burn (deflation)

---

## 9. Vendor Dashboard

### Core Features
- Inventory management (assets, price, stock).
- Order tracking with on-chain payment status.
- Fund settlement and sales history.
- NFT verification tool for physical asset pickup.
- Sales analytics.

### Security
- Web3 wallet login.
- Role-based data isolation.
- Optional multisig for large withdrawals.

### Optional Fiat Gateway
- Convert tokens to fiat via integrated crypto payment gateway.

---

## 10. Asset Claim (Redeem) User Journey
1. Buyer arrives with wallet holding NFT certificate.
2. Vendor scans NFT QR code via dashboard.
3. System verifies ownership and redeem status.
4. Vendor confirms delivery (on-chain update → NFT marked `Redeemed`).
5. Physical asset is handed over.

**Edge Cases:**
- Already redeemed NFT → reject delivery.
- Internet issues → offline verification with later sync.
- NFT not visible → ensure correct wallet address.

---

## 11. Automated Notification Strategy
- **Post-Purchase Confirmation:** NFT receipt notification.
- **Post-Redeem Notification:** Encourage restaking remaining tokens.
- **Retention Reminder:** Exclusive staking tiers for NFT holders.

---

## 12. NFT as Digital Certificate
- Auto-minted upon purchase.
- Stores transaction ID, asset type, and claim status.
- Can be resold before physical redemption.
- Enhances vendor security and transparency.

---

## 13. Buy-Back Feature (Gold)

### Flow
- User requests buy-back using NFT certificate.
- Oracle determines current market price.
- Platform buys back at 97% (example).

### Economics Example
- Buy price: 1,000 tokens
- Market rises to 1,100 tokens
- User receives 1,067 tokens
- Platform earns 33 tokens (spread)

### Liquidity Sources
- Allocation from marketing wallet.
- Vendor-backed reserve pool.

---

## 14. Buy-Back Terms & Conditions (Summary)
- Buy-back only for valid NFT holders.
- Digital (not yet redeemed) = instant.
- Physical (already redeemed) = manual verification.
- Payment only in platform tokens.
- Subject to liquidity availability and token volatility.

---

## 15. Resell (Secondary Market – P2P)
- NFT listed by owner, locked in escrow.
- Buyer pays tokens.
- Distribution:
  - 97% → Seller
  - 3% → Marketing Wallet
- NFT transferred to buyer.
- Vendor notified for off-chain ownership update.

**Note:** NFT transfer represents digital claim only; legal title transfer follows vendor procedures.

---

## 16. Ecosystem Summary
- **Primary Market:** 5% fee to marketing.
- **Secondary Market:** 3% resale royalty.
- **Buy-Back:** 3–5% spread.
- **Staking:** ROI funded by real marketplace activity.

---

**End of English Conversion**


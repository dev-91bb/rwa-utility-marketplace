# Hybrid Proxy - Issues & Fixes

## Purpose

This hybrid proxy pattern protects against **MEV/CPI-MP attacks** during non-atomic proxy deployment.

### The Attack

```
1. Deployer deploys proxy → tx in mempool
2. Attacker sees uninitialized proxy
3. Attacker front-runs initialize() 
4. Attacker becomes owner, can upgrade to malicious code
```

### The Solution

**Immutable ProxyAdmin** - Set in constructor, baked into bytecode. Even if `initialize()` is front-run:
- Attacker becomes token owner (can mint/burn)
- Attacker CANNOT upgrade (requires ProxyAdmin)
- ProxyAdmin is immutable, cannot be changed

---

## Issues Found & Fixed

### 1. hybrid_proxy.sol

| Issue | Problem | Fix |
|-------|---------|-----|
| Immutable in initializer | `immutable` variables must be set in constructor, not `initialize()` | Moved `_proxyAdmin` to constructor |
| Wrong imports | Used non-upgradeable imports | Changed to `@openzeppelin/contracts-upgradeable/...` |
| Conflicting upgrade logic | Both custom `upgradeTo()` and UUPS `_authorizeUpgrade()` | Removed custom, use UUPS only |
| Unnecessary overrides | `_changeAdmin()` and `_admin()` overrides from ERC1967Upgrade | Removed - not needed with pure UUPS |

**Before:**
```solidity
// ❌ Won't work - immutable can't be set in initialize()
address private immutable __proxyAdmin;

function initialize(..., address proxyAdmin_) external initializer {
    __proxyAdmin = proxyAdmin_; // COMPILE ERROR
}
```

**After:**
```solidity
// ✅ Immutable set in constructor - immune to front-running
address private immutable _proxyAdmin;

constructor(address proxyAdmin_) {
    _proxyAdmin = proxyAdmin_;
    _disableInitializers();
}
```

---

### 2. 01.HybridProxyAdmin.sol

| Issue | Problem | Fix |
|-------|---------|-----|
| Deprecated interface | `upgradeTo()` removed in OZ5 UUPS | Use `upgradeToAndCall()` |
| Missing upgradeAndCall | No way to upgrade with initialization data | Added `upgradeAndCall()` function |
| Code duplication | Validation repeated | Extracted to `_validateUpgrade()` |

**Before:**
```solidity
// ❌ OZ5 UUPS doesn't have upgradeTo()
interface IUUPSUpgradeable {
    function upgradeTo(address newImplementation) external;
}
```

**After:**
```solidity
// ✅ OZ5 compatible
interface IUUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}
```

---

### 3. proxyadmin.sol (legacy)

| Issue | Problem | Fix |
|-------|---------|-----|
| Missing imports | Referenced undefined contracts | Use `01.HybridProxyAdmin.sol` instead |
| No Ownable2Step | Single-step ownership transfer | HybridProxyAdmin uses Ownable2Step |

**Recommendation:** Use `01.HybridProxyAdmin.sol` - it has better security with Ownable2Step.

---

### 4. erc1967.sol

| Issue | Problem | Fix |
|-------|---------|-----|
| Custom implementation | Incomplete ERC1967Upgrade wrapper | Just import OZ's ERC1967Proxy |

**After:**
```solidity
// ✅ Use OpenZeppelin directly
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
```

---

## Final Architecture

```
┌─────────────────────────────────────────────────────────┐
│                 HybridProxyAdmin                        │
│                 (Ownable2Step)                          │
│                      │                                  │
│    upgrade()         │         upgradeAndCall()         │
│         │            │              │                   │
│         └────────────┼──────────────┘                   │
│                      ▼                                  │
│            upgradeToAndCall()                           │
└─────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                  ERC1967Proxy                           │
│                      │                                  │
│              delegatecall                               │
│                      ▼                                  │
│           HybridUpgradeableToken                        │
│                      │                                  │
│         _authorizeUpgrade()                             │
│         require(msg.sender == _proxyAdmin)              │
│                      │                                  │
│         _proxyAdmin = IMMUTABLE                         │
│         (set in constructor, baked in bytecode)         │
└─────────────────────────────────────────────────────────┘
```

---

## Deployment Order

```
1. Deploy HybridProxyAdmin(yourAddress)
2. Deploy HybridUpgradeableToken(proxyAdminAddress)  ← immutable set here
3. Encode initialize() calldata
4. Deploy ERC1967Proxy(implementationAddress, initData)
```

Even if step 4 is front-run:
- ✅ ProxyAdmin is immutable in implementation bytecode
- ✅ Only ProxyAdmin can call `upgradeToAndCall()`
- ✅ Attacker cannot upgrade to malicious contract

---

## Security Features

| Feature | Protection |
|---------|------------|
| Immutable `_proxyAdmin` | Cannot be changed after deployment |
| Ownable2Step | Two-step ownership transfer prevents accidents |
| Input validation | Zero address and contract checks |
| UUPS pattern | Upgrade logic in implementation, not proxy |

---

## Files

| File | Purpose | Status |
|------|---------|--------|
| `01.HybridProxyAdmin.sol` | Owner-controlled upgrade manager with Ownable2Step | ✅ Primary |
| `hybrid_proxy.sol` | ERC20 + Permit + UUPS with immutable ProxyAdmin | ✅ Primary |
| `erc1967.sol` | Re-exports OZ ERC1967Proxy | ✅ Use OZ |
| `proxyadmin.sol` | Legacy admin contract | ⚠️ Deprecated |

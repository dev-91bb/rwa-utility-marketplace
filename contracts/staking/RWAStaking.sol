// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RWAStaking
 * @notice Staking with per-second reward calculation and 10% early withdrawal penalty
 */
contract RWAStaking is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error InvalidTier();
    error StakeNotFound();
    error OnlyProxyAdmin();

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint8 tier;
        bool withdrawn;
    }

    address private immutable _proxyAdmin;
    IERC20 public token;
    address public penaltyReceiver;

    uint256 public constant PENALTY_BPS = 1000; // 10%
    uint256 public constant BPS = 10000;
    uint256[4] public lockDurations;
    uint256[4] public aprBps; // Annual rate in BPS (e.g., 1200 = 12% APR)

    mapping(address => Stake[]) public stakes;

    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint8 tier);
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 reward, uint256 penalty);
    event AprUpdated(uint256[4] rates);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    function initialize(
        address token_,
        address owner_,
        address penaltyReceiver_,
        uint256[4] memory aprBps_
    ) external initializer {
        if (token_ == address(0) || owner_ == address(0) || penaltyReceiver_ == address(0)) 
            revert ZeroAddress();

        __Ownable_init(owner_);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        token = IERC20(token_);
        penaltyReceiver = penaltyReceiver_;
        aprBps = aprBps_;

        lockDurations[0] = 30 days;
        lockDurations[1] = 90 days;
        lockDurations[2] = 180 days;
        lockDurations[3] = 365 days;
    }

    function stake(uint256 amount, uint8 tier) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (tier > 3) revert InvalidTier();

        token.safeTransferFrom(msg.sender, address(this), amount);

        stakes[msg.sender].push(Stake({
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + lockDurations[tier],
            tier: tier,
            withdrawn: false
        }));

        emit Staked(msg.sender, stakes[msg.sender].length - 1, amount, tier);
    }

    function unstake(uint256 stakeId) external nonReentrant {
        Stake storage s = stakes[msg.sender][stakeId];
        if (s.amount == 0 || s.withdrawn) revert StakeNotFound();

        s.withdrawn = true;
        uint256 amount = s.amount;
        uint256 reward;
        uint256 penalty;

        if (block.timestamp >= s.endTime) {
            reward = _calculateReward(amount, s.startTime, s.endTime, s.tier);
            token.safeTransfer(msg.sender, amount + reward);
        } else {
            penalty = (amount * PENALTY_BPS) / BPS;
            token.safeTransfer(penaltyReceiver, penalty);
            token.safeTransfer(msg.sender, amount - penalty);
        }

        emit Unstaked(msg.sender, stakeId, amount, reward, penalty);
    }

    function _calculateReward(
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        uint8 tier
    ) internal view returns (uint256) {
        uint256 duration = endTime - startTime;
        // reward = amount * apr * duration / (365 days * BPS)
        return (amount * aprBps[tier] * duration) / (365 days * BPS);
    }

    function pendingReward(address user, uint256 stakeId) external view returns (uint256) {
        Stake storage s = stakes[user][stakeId];
        if (s.amount == 0 || s.withdrawn) return 0;
        
        uint256 elapsed = block.timestamp > s.endTime ? s.endTime - s.startTime : block.timestamp - s.startTime;
        return (s.amount * aprBps[s.tier] * elapsed) / (365 days * BPS);
    }

    function getStakes(address user) external view returns (Stake[] memory) {
        return stakes[user];
    }

    function setApr(uint256[4] memory rates) external onlyOwner {
        aprBps = rates;
        emit AprUpdated(rates);
    }

    function setTierApr(uint8 tier, uint256 rate) external onlyOwner {
        if (tier > 3) revert InvalidTier();
        aprBps[tier] = rate;
        emit AprUpdated(aprBps);
    }

    function setPenaltyReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        penaltyReceiver = receiver;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function proxyAdmin() external view returns (address) { return _proxyAdmin; }
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }
}

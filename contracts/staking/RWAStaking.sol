// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RWAStaking
 * @notice Staking with lock-up tiers + Synthetix-style revenue sharing from rental income
 * @dev Supports lock-up tiers (30/90/180/365 days). All rewards come from external
 *      rental income distributed proportionally via rewardPerToken pattern.
 */
contract RWAStaking is
    AccessControlUpgradeable,
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
    error LockNotExpired();

    error TooEarly();

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint8 tier;
        bool withdrawn;
    }

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    address private immutable _proxyAdmin;
    IERC20 public token;
    address public penaltyReceiver;

    uint256 public constant MIN_STAKE_DURATION = 1 days;

    uint256 public constant PENALTY_BPS = 1000; // 10%
    uint256 public constant BPS = 10000;
    uint256[4] public lockDurations;

    mapping(address => Stake[]) public stakes;

    // --- Synthetix revenue sharing ---
    uint256 public totalStaked;
    uint256 public eligibleStaked; // only stakes older than MIN_STAKE_DURATION
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public revenueRewards; // claimable rental yield

    // --- Per-user active stake tracking ---
    mapping(address => uint256) public userTotalStaked;
    mapping(address => uint256) public userEligibleStaked;

    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint8 tier);
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 penalty);
    event RevenueDistributed(uint256 amount, uint256 newRewardPerToken);
    event RevenueClaimed(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 indexed stakeId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address proxyAdmin_) {
        if (proxyAdmin_ == address(0)) revert ZeroAddress();
        _proxyAdmin = proxyAdmin_;
        _disableInitializers();
    }

    function initialize(
        address token_,
        address admin_,
        address penaltyReceiver_
    ) external initializer {
        if (token_ == address(0) || admin_ == address(0) || penaltyReceiver_ == address(0))
            revert ZeroAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        token = IERC20(token_);
        penaltyReceiver = penaltyReceiver_;

        lockDurations[0] = 30 days;
        lockDurations[1] = 90 days;
        lockDurations[2] = 180 days;
        lockDurations[3] = 365 days;
    }

    // ============ Modifiers ============

    modifier updateRevenue(address account) {
        // Promote newly eligible stakes
        if (account != address(0)) {
            _promoteEligible(account);
        }
        if (account != address(0) && eligibleStaked > 0 && userEligibleStaked[account] > 0) {
            uint256 owed = (userEligibleStaked[account] * (rewardPerTokenStored - userRewardPerTokenPaid[account])) / 1e18;
            revenueRewards[account] += owed;
        }
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    /// @dev Promote stakes that have crossed MIN_STAKE_DURATION into eligible pool
    function _promoteEligible(address account) internal {
        Stake[] storage userStakes = stakes[account];
        uint256 newlyEligible;
        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage s = userStakes[i];
            if (!s.withdrawn && block.timestamp >= s.startTime + MIN_STAKE_DURATION) {
                // Check if this stake was already counted as eligible
                // We use a simple approach: recalculate total eligible from scratch
            }
        }
        // Recalculate user eligible from scratch (simple & correct)
        uint256 total;
        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage s = userStakes[i];
            if (!s.withdrawn && block.timestamp >= s.startTime + MIN_STAKE_DURATION) {
                total += s.amount;
            }
        }
        uint256 prev = userEligibleStaked[account];
        if (total != prev) {
            userEligibleStaked[account] = total;
            eligibleStaked = eligibleStaked - prev + total;
        }
    }

    /// @dev Returns true if user has at least one active stake older than MIN_STAKE_DURATION
    function _hasEligibleStake(address account) internal view returns (bool) {
        Stake[] storage userStakes = stakes[account];
        for (uint256 i = 0; i < userStakes.length; i++) {
            if (!userStakes[i].withdrawn && block.timestamp >= userStakes[i].startTime + MIN_STAKE_DURATION) {
                return true;
            }
        }
        return false;
    }

    // ============ Staking ============

    function stake(uint256 amount, uint8 tier) external nonReentrant whenNotPaused updateRevenue(msg.sender) {
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

        totalStaked += amount;
        userTotalStaked[msg.sender] += amount;

        emit Staked(msg.sender, stakes[msg.sender].length - 1, amount, tier);
    }

    function unstake(uint256 stakeId) external nonReentrant updateRevenue(msg.sender) {
        Stake storage s = stakes[msg.sender][stakeId];
        if (s.amount == 0 || s.withdrawn) revert StakeNotFound();
        if (block.timestamp < s.startTime + MIN_STAKE_DURATION) revert TooEarly();

        s.withdrawn = true;
        uint256 amount = s.amount;

        totalStaked -= amount;
        userTotalStaked[msg.sender] -= amount;
        _promoteEligible(msg.sender);

        uint256 penalty;
        if (block.timestamp < s.endTime) {
            penalty = (amount * PENALTY_BPS) / BPS;
            token.safeTransfer(penaltyReceiver, penalty);
        }
        token.safeTransfer(msg.sender, amount - penalty);

        emit Unstaked(msg.sender, stakeId, amount, penalty);
    }

    /// @notice Admin-triggered emergency withdraw for a user: returns principal, no penalty
    function emergencyWithdraw(address user, uint256 stakeId) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) updateRevenue(user) {
        Stake storage s = stakes[user][stakeId];
        if (s.amount == 0 || s.withdrawn) revert StakeNotFound();

        s.withdrawn = true;
        uint256 amount = s.amount;

        totalStaked -= amount;
        userTotalStaked[user] -= amount;
        _promoteEligible(user);

        token.safeTransfer(user, amount);

        emit EmergencyWithdrawn(user, stakeId, amount);
    }

    // ============ Revenue Sharing (Synthetix) ============

    /// @notice Deposits revenue for proportional distribution to eligible stakers
    function notifyRewardAmount(uint256 amount) external nonReentrant onlyRole(DISTRIBUTOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (eligibleStaked == 0) revert ZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), amount);

        rewardPerTokenStored += (amount * 1e18) / eligibleStaked;

        emit RevenueDistributed(amount, rewardPerTokenStored);
    }

    /// @notice Claim accumulated rental revenue without unstaking
    function claimRevenue() external nonReentrant updateRevenue(msg.sender) {
        uint256 reward = revenueRewards[msg.sender];
        if (reward == 0) revert ZeroAmount();

        revenueRewards[msg.sender] = 0;
        token.safeTransfer(msg.sender, reward);

        emit RevenueClaimed(msg.sender, reward);
    }

    /// @notice View pending rental revenue for a user
    function pendingRevenue(address user) external view returns (uint256) {
        if (!_hasEligibleStake(user)) return revenueRewards[user];
        uint256 eligible = _calcUserEligible(user);
        uint256 owed;
        if (eligibleStaked > 0 && eligible > 0) {
            owed = (eligible * (rewardPerTokenStored - userRewardPerTokenPaid[user])) / 1e18;
        }
        return revenueRewards[user] + owed;
    }

    function _calcUserEligible(address user) internal view returns (uint256 total) {
        Stake[] storage userStakes = stakes[user];
        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage s = userStakes[i];
            if (!s.withdrawn && block.timestamp >= s.startTime + MIN_STAKE_DURATION) {
                total += s.amount;
            }
        }
    }

    // ============ Views ============

    function isStaking(address user) external view returns (bool) {
        return userTotalStaked[user] > 0;
    }

    function getStakes(address user) external view returns (Stake[] memory) {
        return stakes[user];
    }

    // ============ Admin ============

    function setPenaltyReceiver(address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (receiver == address(0)) revert ZeroAddress();
        penaltyReceiver = receiver;
    }

    /// @notice Rescue accidentally sent tokens (cannot rescue the staking token)
    function rescueTokens(address tokenAddr, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenAddr == address(token)) revert ZeroAddress();
        IERC20(tokenAddr).safeTransfer(msg.sender, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    function proxyAdmin() external view returns (address) { return _proxyAdmin; }
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _proxyAdmin) revert OnlyProxyAdmin();
    }
}

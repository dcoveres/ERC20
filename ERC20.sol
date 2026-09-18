pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ProductionERC20
/// @notice ERC20 with immutable cap, optional transfer fee, blacklist, pausing and linear vesting.
/// @dev Intended for OpenZeppelin Contracts 5.x. The project MUST pin an audited OZ release.
contract ProductionERC20 is
    ERC20,
    ERC20Capped,
    ERC20Burnable,
    ERC20Pausable,
    ERC20Permit,
    Ownable2Step
{
    using SafeERC20 for IERC20;

    uint256 public constant MAX_FEE_BPS = 2_000; // 20.00%
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant OWNER_FEE_BPS = 2_500; // 25% of fee

    uint256 public immutable maxSupply;
    uint8 private immutable _tokenDecimals;

    uint256 public feeBps;
    mapping(address => bool) public blacklist;

    struct VestingSchedule {
        uint128 totalAmount;
        uint128 released;
        uint64 start;
        uint64 cliff;
        uint64 duration;
        bool exists;
    }

    mapping(address => VestingSchedule) public vestingSchedules;
    uint256 public totalReserved;

    event FeeBpsUpdated(uint256 indexed oldFeeBps, uint256 indexed newFeeBps);
    event BlacklistUpdated(address indexed account, bool blacklisted);
    event VestingCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration
    );
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event ContractFeesWithdrawn(address indexed to, uint256 amount);
    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error InvalidCap();
    error InvalidFee();
    error BlacklistedAddress(address account);
    error AmountZero();
    error InsufficientFreeBalance();
    error InvalidVesting();
    error VestingAlreadyExists();
    error NoVesting();
    error NothingToRelease();
    error ReservedBalanceViolation();
    error CannotRescueSelf();
    error AmountTooLarge();
    error CannotBlacklistOwner();

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_,
        address initialOwner_
    )
        ERC20(name_, symbol_)
        ERC20Capped(cap_)
        ERC20Permit(name_)
        Ownable(initialOwner_)
    {
        if (cap_ == 0 || initialOwner_ == address(0)) revert InvalidCap();
        maxSupply = cap_;
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (blacklist[to]) revert BlacklistedAddress(to);
        if (amount == 0) revert AmountZero();

        _mint(to, amount);
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert InvalidFee();

        uint256 old = feeBps;
        feeBps = newFeeBps;
        emit FeeBpsUpdated(old, newFeeBps);
    }

    function setBlacklist(address account, bool value) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        if (account == owner()) revert CannotBlacklistOwner();

        blacklist[account] = value;
        emit BlacklistUpdated(account, value);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Withdraw only unreserved token fees held by this contract.
    function withdrawContractFees(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = balanceOf(address(this));
        if (balance < totalReserved) revert ReservedBalanceViolation();

        uint256 freeBalance = balance - totalReserved;
        if (amount > freeBalance) revert InsufficientFreeBalance();

        _transfer(address(this), to, amount);
        emit ContractFeesWithdrawn(to, amount);
    }

    function createVesting(
        address beneficiary,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration
    ) external onlyOwner {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (blacklist[beneficiary]) revert BlacklistedAddress(beneficiary);
        if (totalAmount == 0) revert AmountZero();
        if (duration == 0 || cliff > duration) revert InvalidVesting();
        if (totalAmount > type(uint128).max) revert AmountTooLarge();
        if (start < block.timestamp) revert InvalidVesting();
        if (start > type(uint64).max || cliff > type(uint64).max || duration > type(uint64).max) {
            revert InvalidVesting();
        }

        VestingSchedule storage existing = vestingSchedules[beneficiary];
        if (existing.exists) revert VestingAlreadyExists();

        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance < totalReserved) revert ReservedBalanceViolation();
        if (contractBalance - totalReserved < totalAmount) revert InsufficientFreeBalance();

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: uint128(totalAmount),
            released: 0,
            start: uint64(start),
            cliff: uint64(cliff),
            duration: uint64(duration),
            exists: true
        });

        totalReserved += totalAmount;

        emit VestingCreated(
            beneficiary,
            totalAmount,
            start,
            cliff,
            duration
        );
    }

    function releaseVestedTokens() external {
        _requireNotBlacklisted(msg.sender);

        uint256 amount = releasableAmount(msg.sender);
        if (amount == 0) revert NothingToRelease();

        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        schedule.released += uint128(amount);
        totalReserved -= amount;

        _transfer(address(this), msg.sender, amount);
        emit TokensReleased(msg.sender, amount);
    }

    function vestedAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        if (!schedule.exists) return 0;

        uint256 start = schedule.start;
        uint256 cliffEnd = start + schedule.cliff;
        uint256 end = start + schedule.duration;

        if (block.timestamp < cliffEnd) return 0;
        if (block.timestamp >= end) return schedule.totalAmount;

        uint256 vestingPeriod = schedule.duration - schedule.cliff;
        if (vestingPeriod == 0) return 0;

        uint256 elapsed = block.timestamp - cliffEnd;
        return (uint256(schedule.totalAmount) * elapsed) / vestingPeriod;
    }

    function releasableAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        if (!schedule.exists) return 0;

        uint256 vested = vestedAmount(beneficiary);
        uint256 released = schedule.released;

        return vested > released ? vested - released : 0;
    }


    /// @notice Renouncing ownership also permanently disables transfer fees.
    /// @dev This preserves the behavior of the original contract while preventing
    ///      fees from being sent to address(0) after ownership is renounced.
    function renounceOwnership() public override onlyOwner {
        feeBps = 0;
        emit FeeBpsUpdated(feeBps, 0);
        super.renounceOwnership();
    }

    /// @notice Rescue another ERC20 accidentally sent to this contract.
    /// @dev The token's own balance is intentionally not rescuable.
    function rescueTokens(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (address(token) == address(this)) revert CannotRescueSelf();
        if (to == address(0)) revert ZeroAddress();

        token.safeTransfer(to, amount);
        emit ERC20Rescued(address(token), to, amount);
    }

    function _requireNotBlacklisted(address account) internal view {
        if (blacklist[account]) revert BlacklistedAddress(account);
    }

    function _update(
        address from,
        address to,
        uint256 value
    )
        internal
        override(ERC20, ERC20Capped, ERC20Pausable)
    {
        if (from != address(0)) _requireNotBlacklisted(from);
        if (to != address(0)) _requireNotBlacklisted(to);

        if (
            feeBps == 0 ||
            from == address(0) ||
            to == address(0) ||
            from == address(this) ||
            to == address(this)
        ) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = (value * feeBps) / BPS_DENOMINATOR;
        uint256 recipientAmount = value - fee;
        uint256 ownerFee = (fee * OWNER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 contractFee = fee - ownerFee;

        super._update(from, to, recipientAmount);

        if (ownerFee != 0) {
            super._update(from, owner(), ownerFee);
        }

        if (contractFee != 0) {
            super._update(from, address(this), contractFee);
        }
    }
}

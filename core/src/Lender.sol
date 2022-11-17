// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ImmutableArgs} from "clones-with-immutable-args/ImmutableArgs.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {FullMath} from "./libraries/FullMath.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

import {InterestModel} from "./InterestModel.sol";
import {Factory} from "./Factory.sol";

interface IFlashBorrower {
    function onFlashLoan(address initiator, uint256 amount, bytes calldata data) external;
}

contract Lender {
    using SafeTransferLib for ERC20;
    using FullMath for uint256;
    using SafeCastLib for uint256;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    uint256 public constant ONE = 1e12;

    uint256 public constant BORROWS_SCALER = type(uint72).max * ONE; // uint72 is from borrowIndex type

    Factory public immutable FACTORY;

    address public immutable TREASURY;

    InterestModel public immutable INTEREST_MODEL;

    struct Cache {
        uint256 totalSupply;
        uint256 lastBalance;
        uint256 lastAccrualTime;
        uint256 borrowBase;
        uint256 borrowIndex;
    }

    uint112 public totalSupply;

    uint112 public lastBalance;

    uint32 public lastAccrualTime;

    uint184 public borrowBase;

    uint72 public borrowIndex;

    mapping(address => uint256) public balanceOf;

    mapping(address => uint256) public borrows;

    constructor(address treasury, InterestModel interestModel) {
        FACTORY = Factory(msg.sender);
        TREASURY = treasury;
        INTEREST_MODEL = interestModel;
    }

    function initialize() public virtual {
        require(borrowIndex == 0, "Already initialized"); // TODO use real Error
        borrowIndex = uint72(ONE);
        lastAccrualTime = uint32(block.timestamp);
    }

    function deposit(uint256 amount, address beneficiary) external returns (uint256 shares) {
        Cache memory cache = _load();

        uint256 inventory;
        (cache, inventory) = _accrueInterest(cache);

        shares = _convertToShares(amount, inventory, cache.totalSupply);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Ensure tokens were transferred
        cache.lastBalance += amount;
        require(cache.lastBalance <= asset().balanceOf(address(this)));

        // Mint shares (emits event that can be interpreted as a deposit)
        cache.totalSupply += shares;
        _unsafeMint(beneficiary, shares);

        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function withdraw(uint256 shares, address recipient) external returns (uint256 amount) {
        Cache memory cache = _load();

        uint256 inventory;
        (cache, inventory) = _accrueInterest(cache);

        if (shares == type(uint256).max) shares = balanceOf[msg.sender];
        amount = _convertToAssets(shares, inventory, cache.totalSupply);
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        // Transfer tokens
        cache.lastBalance -= amount;
        asset().safeTransfer(recipient, amount);

        // Burn shares (emits event that can be interpreted as a withdrawal)
        _unsafeBurn(msg.sender, shares);
        unchecked {
            cache.totalSupply -= shares;
        }

        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function borrow(uint256 amount, address recipient) external {
        require(FACTORY.isBorrowerAllowed(this, msg.sender), "Aloe: bad account");

        Cache memory cache = _load();

        (cache, ) = _accrueInterest(cache);

        uint256 base = amount.mulDivRoundingUp(BORROWS_SCALER, cache.borrowIndex);
        cache.borrowBase += base;
        unchecked {
            borrows[msg.sender] += base;
        }

        // Transfer tokens
        cache.lastBalance -= amount;
        asset().safeTransfer(recipient, amount);

        _save(cache, /* didChangeBorrowBase: */ true);
        // TODO emit event
    }

    function repay(uint256 amount, address beneficiary) external {
        Cache memory cache = _load();

        (cache, ) = _accrueInterest(cache);

        // TODO if `amount` == type(uint256).max, repay max
        // if (amount == type(uint256).max) amount = borrows[to].mulDivRoundingUp(cache.borrowIndex, BORROWS_SCALER);
        uint256 base = amount.mulDiv(BORROWS_SCALER, cache.borrowIndex);
        borrows[beneficiary] -= base;
        unchecked {
            cache.borrowBase -= base;
        }

        // Ensure tokens were transferred
        cache.lastBalance += amount;
        require(cache.lastBalance <= asset().balanceOf(address(this)));

        _save(cache, /* didChangeBorrowBase: */ true);
        // TODO emit event
    }

    /// @dev Reentrancy guard is critical here! Without it, one could use a flash loan to repay a normal loan.
    function flash(uint256 amount, address to, bytes calldata data) external {
        // Reentrancy guard
        uint32 _lastAccrualTime = lastAccrualTime;
        require(_lastAccrualTime != 0);
        lastAccrualTime = 0;

        ERC20 asset_ = asset();

        uint256 balance = asset_.balanceOf(address(this));
        asset_.safeTransfer(to, amount);
        IFlashBorrower(to).onFlashLoan(msg.sender, amount, data);
        require(asset_.balanceOf(address(this)) == balance, "Aloe: failed repay"); // TODO use real Error

        lastAccrualTime = _lastAccrualTime;
    }

    function accrueInterest() external {
        Cache memory cache = _load();
        (cache, ) = _accrueInterest(cache);
        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function _accrueInterest(Cache memory cache) private returns (Cache memory, uint256) {
        uint256 inventory;
        uint256 newTotalSupply;
        (cache, inventory, newTotalSupply) = _accrueInterestView(cache);

        if (newTotalSupply != cache.totalSupply) {
            _unsafeMint(TREASURY, newTotalSupply - cache.totalSupply);
            cache.totalSupply = newTotalSupply;
        }

        return (cache, inventory);
    }

    function _load() private returns (Cache memory cache) {
        cache = Cache(totalSupply, lastBalance, lastAccrualTime, borrowBase, borrowIndex);
        // Reentrancy guard
        require(cache.lastAccrualTime != 0);
        lastAccrualTime = 0;
    }

    function _save(Cache memory cache, bool didChangeBorrowBase) private {
        if (cache.lastAccrualTime == 0) {
            // `cache.lastAccrualTime == 0` implies that `cache.borrowIndex` was updated.
            // `cache.borrowBase` MAY also have been updated, so we store both components of the slot.
            borrowBase = cache.borrowBase.safeCastTo184();
            borrowIndex = cache.borrowIndex.safeCastTo72();
            // Now that we've read the flag, we can update `cache.lastAccrualTime` to a more appropriate value
            cache.lastAccrualTime = block.timestamp;

        } else if (didChangeBorrowBase) {
            // Here, `cache.lastAccrualTime` is a real timestamp (could be `block.timestamp` or older). We can infer
            // that `cache.borrowIndex` was *not* updated. So we only have to store `cache.borrowBase`.
            borrowBase = cache.borrowBase.safeCastTo184();
        }

        totalSupply = cache.totalSupply.safeCastTo112();
        lastBalance = cache.lastBalance.safeCastTo112();
        lastAccrualTime = cache.lastAccrualTime.safeCastTo32(); // Disables reentrancy guard
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev You must do `totalSupply += amount` separately. Do so in a checked context.
    function _unsafeMint(address to, uint256 amount) private {
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    /// @dev You must do `totalSupply -= amount` separately. Do so in an unchecked context.
    function _unsafeBurn(address from, uint256 amount) private {
        balanceOf[from] -= amount;

        emit Transfer(from, address(0), amount);
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function balanceOfUnderlying(address account) external view returns (uint256) {
        // TODO this should probably accrueInterest
        return _convertToAssets({
            shares: balanceOf[account],
            inventory: lastBalance + FullMath.mulDiv(borrowBase, borrowIndex, BORROWS_SCALER),
            totalSupply_: totalSupply
        });
    }

    // TODO this is really borrowBalanceStored, not Current (in Compound lingo)
    function borrowBalanceCurrent(address account) external view returns (uint256) {
        return borrows[account].mulDiv(borrowIndex, BORROWS_SCALER);
    }

    // TODO exchangeRateCurrent and stored

    // TODO utilizationCurrent and stored

    // TODO inventoryCurrent and stored

    function _accrueInterestView(Cache memory cache) private view returns (Cache memory, uint256, uint256) {
        (uint256 borrowsOld, uint256 accrualFactor) = _getAccrualFactor(cache);
        if (accrualFactor == 0 || borrowsOld == 0) return (cache, cache.lastBalance, cache.totalSupply);

        // TODO sane constraints on accrualFactor WITH TESTS for when accrualFactor is reported to be massive
        cache.borrowIndex = cache.borrowIndex.mulDiv(ONE + accrualFactor, ONE);
        cache.lastAccrualTime = 0; // 0 in storage means locked to reentrancy; 0 in `cache` means `borrowIndex` was updated

        // re-compute borrows and inventory
        uint256 borrowsNew = cache.borrowBase.mulDiv(cache.borrowIndex, BORROWS_SCALER);
        uint256 inventory;
        unchecked {
            inventory = cache.lastBalance + borrowsNew;
        }

        uint256 newTotalSupply = cache.totalSupply.mulDiv(
            inventory,
            inventory - (borrowsNew - borrowsOld) / 8 // `8` indicates a 1/8=12.5% reserve factor
        );
        return (cache, inventory, newTotalSupply);
    }

    function _getAccrualFactor(Cache memory cache) private view returns (uint256 totalBorrows, uint256 accrualFactor) {
        if (cache.lastAccrualTime != block.timestamp && cache.borrowBase != 0) {
            // compute `totalBorrows`
            totalBorrows = cache.borrowBase.mulDiv(cache.borrowIndex, BORROWS_SCALER);
            // get `accrualFactor`
            accrualFactor = INTEREST_MODEL.getAccrualFactor({
                elapsedTime: block.timestamp - cache.lastAccrualTime,
                utilization: uint256(1e18).mulDiv(totalBorrows, totalBorrows + cache.lastBalance)
            });
        }
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() public pure returns (ERC20) {
        return ERC20(ImmutableArgs.addr());
    }

    function _convertToShares(
        uint256 assets,
        uint256 inventory,
        uint256 totalSupply_
    ) internal pure returns (uint256 shares) {
        shares = (totalSupply_ == 0) ? assets : assets.mulDiv(totalSupply_, inventory);
    }

    function _convertToAssets(
        uint256 shares,
        uint256 inventory,
        uint256 totalSupply_
    ) internal pure returns (uint256 assets) {
        assets = (totalSupply_ == 0) ? 0 : shares.mulDiv(inventory, totalSupply_);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {FullMath} from "./libraries/FullMath.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

import {KERC20} from "./KERC20.sol";
import {InterestModel} from "./InterestModel.sol";
import {Factory} from "./Factory.sol";

interface IFlashBorrower {
    function onFlashLoan(address initiator, uint256 amount, bytes calldata data) external;
}

contract Kitty is KERC20 {
    using SafeTransferLib for ERC20;
    using FullMath for uint256;
    using SafeCastLib for uint256;

    uint256 public constant ONE = 1e12;

    uint256 public constant BORROWS_SCALER = type(uint72).max * ONE; // uint72 is from borrowIndex type

    Factory public immutable FACTORY;

    ERC20 public immutable ASSET;

    InterestModel public immutable INTEREST_MODEL;

    address public immutable TREASURY;

    struct Cache {
        uint256 totalSupply;
        uint256 lastBalance;
        uint256 lastAccrualTime;
        uint256 borrowBase;
        uint256 borrowIndex;
    }

    // uint112 public totalSupply; // phantom variable inherited from KERC20

    uint112 public lastBalance;

    uint32 public lastAccrualTime;

    uint184 public borrowBase;

    uint72 public borrowIndex;

    mapping(address => uint256) public borrows;

    constructor(ERC20 _asset, InterestModel _interestModel, address _treasury)
        KERC20(
            string.concat("Aloe II ", _asset.name()),
            string.concat(_asset.symbol(), "+"),
            _asset.decimals()
        )
    {
        FACTORY = Factory(msg.sender);
        ASSET = _asset;
        INTEREST_MODEL = _interestModel;
        TREASURY = _treasury;

        borrowIndex = uint72(ONE);
        lastAccrualTime = uint32(block.timestamp);
    }

    function deposit(uint256 amount, address beneficiary) external returns (uint256 shares) {
        (Cache memory cache) = _load();

        uint256 inventory;
        (cache, inventory) = _accrueInterest(cache);

        shares = _computeShares(cache.totalSupply, inventory, amount);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Ensure tokens were transferred
        cache.lastBalance += amount;
        require(cache.lastBalance <= ASSET.balanceOf(address(this)));

        // Mint shares (emits event that can be interpreted as a deposit)
        cache.totalSupply += shares;
        _unsafeMint(beneficiary, shares);

        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function withdraw(uint256 shares, address recipient) external returns (uint256 amount) {
        (Cache memory cache) = _load();

        uint256 inventory;
        (cache, inventory) = _accrueInterest(cache);

        if (shares == type(uint256).max) shares = balanceOf[msg.sender];
        amount = shares.mulDiv(inventory, cache.totalSupply);
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        // Transfer tokens
        cache.lastBalance -= amount;
        ASSET.safeTransfer(recipient, amount);

        // Burn shares (emits event that can be interpreted as a withdrawal)
        _unsafeBurn(msg.sender, shares);
        unchecked {
            cache.totalSupply -= shares;
        }

        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function borrow(uint256 amount, address recipient) external {
        require(FACTORY.isMarginAccountAllowed(this, msg.sender), "Aloe: bad account");

        (Cache memory cache) = _load();

        (cache, ) = _accrueInterest(cache);

        uint256 base = amount.mulDivRoundingUp(BORROWS_SCALER, cache.borrowIndex);
        cache.borrowBase += base;
        unchecked {
            borrows[msg.sender] += base;
        }

        // Transfer tokens
        cache.lastBalance -= amount;
        ASSET.safeTransfer(recipient, amount);

        _save(cache, /* didChangeBorrowBase: */ true);
    }

    function repay(uint256 amount, address beneficiary) external {
        (Cache memory cache) = _load();

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
        require(cache.lastBalance <= ASSET.balanceOf(address(this)));

        _save(cache, /* didChangeBorrowBase: */ true);
    }

    /// @dev Reentrancy guard is critical here! Without it, one could use a flash loan to repay a normal loan.
    function flash(uint256 amount, address to, bytes calldata data) external {
        // Reentrancy guard
        uint32 _lastAccrualTime = lastAccrualTime;
        require(_lastAccrualTime != 0);
        lastAccrualTime = 0;

        uint256 balance = ASSET.balanceOf(address(this));
        ASSET.safeTransfer(to, amount);
        IFlashBorrower(to).onFlashLoan(msg.sender, amount, data);
        require(ASSET.balanceOf(address(this)) == balance, "Aloe: failed repay"); // TODO use real Error

        lastAccrualTime = _lastAccrualTime;
    }

    function accrueInterest() external {
        (Cache memory cache) = _load();
        (cache, ) = _accrueInterest(cache);
        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function _accrueInterest(Cache memory cache) private returns (Cache memory, uint256) {
        (uint256 borrowsOld, uint256 accrualFactor) = _getAccrualFactor(cache);
        if (accrualFactor == 0 || borrowsOld == 0) return (cache, cache.lastBalance); 

        // TODO sane constraints on accrualFactor WITH TESTS for when accrualFactor is reported to be massive
        cache.borrowIndex = cache.borrowIndex.mulDiv(ONE + accrualFactor, ONE);
        cache.lastAccrualTime = block.timestamp;

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
        totalSupply = cache.totalSupply.safeCastTo112();
        lastBalance = cache.lastBalance.safeCastTo112();
        lastAccrualTime = cache.lastAccrualTime.safeCastTo32();

        if (didChangeBorrowBase || cache.lastAccrualTime != block.timestamp) {
            borrowBase = uint184(cache.borrowBase); // As long as `lastBalance` is safe-casted, this doesn't need to be
            borrowIndex = cache.borrowIndex.safeCastTo72();
        }
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    // TODO use ERC4626-style function names
    function balanceOfUnderlying(address account) external view returns (uint256) {
        // TODO this should probably accrueInterest
        return balanceOf[account].mulDiv(lastBalance + FullMath.mulDiv(borrowBase, borrowIndex, BORROWS_SCALER), totalSupply); // TODO fails when totalSupply = 0
    }

    // TODO this is really borrowBalanceStored, not Current (in Compound lingo)
    function borrowBalanceCurrent(address account) external view returns (uint256) {
        return borrows[account].mulDiv(borrowIndex, BORROWS_SCALER);
    }

    // TODO exchangeRateCurrent and stored

    // TODO utilizationCurrent and stored

    // TODO inventoryCurrent and stored

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

    function _computeShares(
        uint256 _totalSupply,
        uint256 _inventory,
        uint256 _amount
    ) private pure returns (uint256) {
        return (_totalSupply == 0) ? _amount : _amount.mulDiv(_totalSupply, _inventory);
    }
}

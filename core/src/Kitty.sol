// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {FullMath} from "./libraries/FullMath.sol";

import {KERC20} from "./KERC20.sol";
import {InterestModel} from "./InterestModel.sol";
import {Factory} from "./Factory.sol";

/**
 * TODO: enable flash loans
 */
contract Kitty is KERC20 {
    using SafeTransferLib for ERC20;
    using FullMath for uint256;

    uint256 public constant INTERNAL_PRECISION = 1e12;

    uint256 public constant BORROWS_SCALER = type(uint72).max * INTERNAL_PRECISION; // uint72 is from borrowIndex type

    Factory public immutable FACTORY;

    ERC20 public immutable ASSET;

    InterestModel public immutable INTEREST_MODEL;

    address public immutable TREASURY;

    struct Cache {
        uint112 totalSupply;
        uint112 lastBalance;
        uint32 lastAccrualTime;
        uint184 borrowBase;
        uint72 borrowIndex;
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

        borrowIndex = uint72(INTERNAL_PRECISION);
        lastAccrualTime = uint32(block.timestamp);
    }

    // TODO prevent new deposits after 2100
    function deposit(uint256 amount, address to) external returns (uint256 shares) {
        (Cache memory cache) = _load();

        uint256 inventory;
        (cache, inventory) = _accrueInterest(cache);

        shares = _computeShares(cache.totalSupply, inventory, amount);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Ensure tokens were transferred
        cache.lastBalance += uint112(amount); // TODO safe casting
        require(cache.lastBalance <= ASSET.balanceOf(address(this)));

        // Mint shares (emits event that can be interpreted as a deposit)
        cache.totalSupply += uint112(shares); // TODO safe casting
        _unsafeMint(to, shares);

        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function withdraw(uint256 shares, address to) external returns (uint256 amount) {
        (Cache memory cache) = _load();

        uint256 inventory;
        (cache, inventory) = _accrueInterest(cache);

        if (shares == type(uint256).max) shares = balanceOf[msg.sender];
        amount = inventory.mulDiv(shares, cache.totalSupply);
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        // Transfer tokens
        cache.lastBalance -= uint112(amount); // TODO safe casting
        ASSET.safeTransfer(to, amount);

        // Burn shares (emits event that can be interpreted as a withdrawal)
        _unsafeBurn(msg.sender, shares);
        unchecked {
            cache.totalSupply -= uint112(shares); // don't need safe casting here because burn was successful
        }

        _save(cache, /* didChangeBorrowBase: */ false);
    }

    // TODO prevent new borrows after 2100
    function borrow(uint256 amount, address to) external {
        require(FACTORY.isMarginAccountAllowed(this, msg.sender), "Aloe: bad account");

        (Cache memory cache) = _load();

        (cache, ) = _accrueInterest(cache);

        uint256 base = amount.mulDivRoundingUp(BORROWS_SCALER, cache.borrowIndex);
        cache.borrowBase += uint184(base); // don't need safe casting here as long as `amount` is safe-casted below
        unchecked {
            borrows[msg.sender] += base;
        }

        // Transfer tokens
        cache.lastBalance -= uint112(amount); // TODO safe casting
        ASSET.safeTransfer(to, amount);
        
        _save(cache, /* didChangeBorrowBase: */ true);
    }

    function repay(uint256 amount, address to) external {
        (Cache memory cache) = _load();

        (cache, ) = _accrueInterest(cache);

        // TODO if `amount` == type(uint256).max, repay max
        // if (amount == type(uint256).max) amount = borrows[to].mulDivRoundingUp(cache.borrowIndex, BORROWS_SCALER);
        uint256 base = amount.mulDiv(BORROWS_SCALER, cache.borrowIndex);
        borrows[to] -= base;
        unchecked {
            cache.borrowBase -= uint184(base); // don't need safe casting here as long as `amount` is safe-casted below
        }

        // Ensure tokens were transferred
        cache.lastBalance += uint112(amount); // TODO safe casting
        require(cache.lastBalance <= ASSET.balanceOf(address(this)));

        _save(cache, /* didChangeBorrowBase: */ true);
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
        cache.borrowIndex = uint72(FullMath.mulDiv(cache.borrowIndex, INTERNAL_PRECISION + accrualFactor, INTERNAL_PRECISION));
        cache.lastAccrualTime = uint32(block.timestamp); // TODO safe casting

        // re-compute borrows and inventory
        uint256 borrowsNew = FullMath.mulDiv(cache.borrowBase, cache.borrowIndex, BORROWS_SCALER);
        uint256 inventory;
        unchecked {
            inventory = cache.lastBalance + borrowsNew;
        }

        uint256 newTotalSupply = FullMath.mulDiv(
            cache.totalSupply,
            inventory,
            inventory - (borrowsNew - borrowsOld) / 8 // `8` indicates a 1/8=12.5% reserve factor
        );
        if (newTotalSupply != cache.totalSupply) {
            _unsafeMint(TREASURY, newTotalSupply - cache.totalSupply);
            cache.totalSupply = uint112(newTotalSupply); // TODO safe casting
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
        totalSupply = cache.totalSupply;
        lastBalance = cache.lastBalance;
        lastAccrualTime = cache.lastAccrualTime;

        if (didChangeBorrowBase || cache.lastAccrualTime != block.timestamp) {
            borrowBase = cache.borrowBase;
            borrowIndex = cache.borrowIndex;
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
        return FullMath.mulDiv(borrows[account], borrowIndex, BORROWS_SCALER);
    }

    // TODO exchangeRateCurrent and stored

    // TODO utilizationCurrent and stored

    // TODO inventoryCurrent and stored

    function _getAccrualFactor(Cache memory cache) private view returns (uint256 totalBorrows, uint256 accrualFactor) {
        if (cache.lastAccrualTime != block.timestamp && cache.borrowBase != 0) {
            // compute `totalBorrows`
            totalBorrows = FullMath.mulDiv(cache.borrowBase, cache.borrowIndex, BORROWS_SCALER);
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
        return (_totalSupply == 0) ? _amount : FullMath.mulDiv(_amount, _totalSupply, _inventory);
    }
}

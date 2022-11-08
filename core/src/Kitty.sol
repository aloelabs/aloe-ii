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

    struct Slot0 {
        uint112 totalSupply;
        uint112 lastBalance;
        uint32 lastAccrualTime;
    }

    // uint112 public totalSupply; // phantom variable inherited from ERC20

    uint112 public lastBalance;

    uint32 public lastAccrualTime;

    struct Slot1 {
        uint184 borrowBase;
        uint72 borrowIndex;
    }

    uint184 public borrowBase;

    uint72 public borrowIndex;

    mapping(address => uint256) public borrows;

    constructor(ERC20 _asset, InterestModel _interestModel, address _treasury)
        KERC20(
            string.concat("Aloe II ", _asset.name()),
            string.concat(_asset.symbol(), "+"),
            18 // TODO decide magnitude of internal bookkeeping
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
    function deposit(uint112 amount, address to) external returns (uint112 shares) {
        (Slot0 memory slot0, Slot1 memory slot1) = _load();

        // Reentrancy guard
        require(slot0.lastAccrualTime != 0);
        lastAccrualTime = 0;

        uint256 inventory;
        (slot0, slot1, inventory) = _accrueInterest(slot0, slot1);

        shares = _computeShares(slot0.totalSupply, inventory, amount);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Ensure tokens were transferred
        slot0.lastBalance += amount;
        require(slot0.lastBalance <= ASSET.balanceOf(address(this)));

        // Mint shares (emits event that can be interpreted as a deposit)
        slot0.totalSupply += shares;
        _unsafeMint(to, shares);

        _save(slot0, slot1); // TODO if inventory == slot0.lastBalance, then no interest was accrued, and we don't need to write slot1 to storage
    }

    function withdraw(uint112 shares, address to) external returns (uint112 amount) {
        (Slot0 memory slot0, Slot1 memory slot1) = _load();

        // Reentrancy guard
        require(slot0.lastAccrualTime != 0);
        lastAccrualTime = 0;

        uint256 inventory;
        (slot0, slot1, inventory) = _accrueInterest(slot0, slot1);

        // TODO if `shares` == type(uint112).max, withdraw max
        amount = uint112(inventory.mulDiv(shares, slot0.totalSupply)); // TODO safe casting
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        // Transfer tokens
        slot0.lastBalance -= amount;
        ASSET.safeTransfer(to, amount);

        // Burn shares (emits event that can be interpreted as a withdrawal)
        _unsafeBurn(msg.sender, shares);
        unchecked {
            slot0.totalSupply -= shares;
        }

        _save(slot0, slot1); // TODO if inventory == slot0.lastBalance, then no interest was accrued, and we don't need to write slot1 to storage
    }

    // TODO prevent new borrows after 2100
    function borrow(uint256 amount, address to) external {
        require(FACTORY.isMarginAccountAllowed(this, msg.sender), "Aloe: bad account");

        (Slot0 memory slot0, Slot1 memory slot1) = _load();

        // Reentrancy guard
        require(slot0.lastAccrualTime != 0);
        lastAccrualTime = 0;

        (slot0, slot1, ) = _accrueInterest(slot0, slot1);

        uint256 base = amount.mulDivRoundingUp(BORROWS_SCALER, slot1.borrowIndex);
        borrows[msg.sender] += base;
        slot1.borrowBase += uint184(base); // TODO safe casting

        // Transfer tokens
        slot0.lastBalance -= uint112(amount); // TODO safe casting
        ASSET.safeTransfer(to, amount);
        
        _save(slot0, slot1);
    }

    function repay(uint256 amount, address to) external {
        (Slot0 memory slot0, Slot1 memory slot1) = _load();

        // Reentrancy guard
        require(slot0.lastAccrualTime != 0);
        lastAccrualTime = 0;

        (slot0, slot1, ) = _accrueInterest(slot0, slot1);

        // TODO if `amount` == type(uint256).max, repay max
        uint256 base = amount.mulDiv(BORROWS_SCALER, slot1.borrowIndex);
        borrows[to] -= base;
        slot1.borrowBase -= uint184(base); // TODO safe casting

        // Ensure tokens were transferred
        slot0.lastBalance += uint112(amount); // TODO safe casting
        require(slot0.lastBalance <= ASSET.balanceOf(address(this)));

        _save(slot0, slot1);
    }

    function accrueInterest() external {
        (Slot0 memory slot0, Slot1 memory slot1) = _load();

        // Reentrancy guard
        require(slot0.lastAccrualTime != 0);
        lastAccrualTime = 0;

        (slot0, slot1, ) = _accrueInterest(slot0, slot1);

        _save(slot0, slot1); // TODO if inventory == slot0.lastBalance, then no interest was accrued, and we don't need to write slot1 to storage
    }

    function _accrueInterest(Slot0 memory slot0, Slot1 memory slot1) private returns (Slot0 memory, Slot1 memory, uint256) {
        (uint256 borrowsOld, uint256 accrualFactor) = _getAccrualFactor(slot0, slot1);
        if (accrualFactor == 0 || borrowsOld == 0) return (slot0, slot1, slot0.lastBalance); 

        // TODO sane constraints on accrualFactor WITH TESTS for when accrualFactor is reported to be massive
        slot1.borrowIndex = uint72(FullMath.mulDiv(slot1.borrowIndex, INTERNAL_PRECISION + accrualFactor, INTERNAL_PRECISION));
        slot0.lastAccrualTime = uint32(block.timestamp); // TODO probably don't need to pass this around. removing would make func more pure.

        // re-compute borrows and inventory
        uint256 borrowsNew = FullMath.mulDiv(slot1.borrowBase, slot1.borrowIndex, BORROWS_SCALER);
        uint256 inventory;
        unchecked {
            inventory = slot0.lastBalance + borrowsNew;
        }

        uint256 newTotalSupply = FullMath.mulDiv(
            slot0.totalSupply,
            inventory,
            inventory - (borrowsNew - borrowsOld) / 8 // `8` indicates a 1/8=12.5% reserve factor
        );
        if (newTotalSupply != slot0.totalSupply) {
            _unsafeMint(TREASURY, newTotalSupply - slot0.totalSupply);
            slot0.totalSupply = uint112(newTotalSupply); // TODO safe casting
        }

        return (slot0, slot1, inventory);
    }

    function _save(Slot0 memory slot0, Slot1 memory slot1) private {
        totalSupply = slot0.totalSupply;
        lastBalance = slot0.lastBalance;
        lastAccrualTime = slot0.lastAccrualTime; // TODO don't put in memory struct, and instead just set to block.timestamp
        // TODO in cases where interest has already accrued this block, we actually don't have to write to slot1 storage
        // for deposit and withdraw. (neither borrowBase nor borrowIndex change)
        borrowBase = slot1.borrowBase;
        borrowIndex = slot1.borrowIndex;
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _load() private view returns (Slot0 memory slot0, Slot1 memory slot1) {
        slot0 = Slot0(totalSupply, lastBalance, lastAccrualTime);
        slot1 = Slot1(borrowBase, borrowIndex);
    }

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

    function _getAccrualFactor(Slot0 memory slot0, Slot1 memory slot1) private view returns (uint256 totalBorrows, uint256 accrualFactor) {
        if (slot0.lastAccrualTime != block.timestamp && slot1.borrowBase != 0) {
            // compute `borrows`
            totalBorrows = FullMath.mulDiv(slot1.borrowBase, slot1.borrowIndex, BORROWS_SCALER);
            // get `accrualFactor`
            accrualFactor = INTEREST_MODEL.getAccrualFactor({
                elapsedTime: block.timestamp - slot0.lastAccrualTime,
                utilization: uint256(1e18).mulDiv(totalBorrows, totalBorrows + slot0.lastBalance)
            });
        }
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _computeShares(
        uint112 _totalSupply,
        uint256 _inventory,
        uint112 _amount
    ) private pure returns (uint112) {
        return (_totalSupply == 0) ? _amount : uint112(FullMath.mulDiv(_amount, _totalSupply, _inventory)); // TODO safe casting
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";

import {FullMath} from "src/libraries/FullMath.sol";

import {InterestModel} from "src/InterestModel.sol";

/**
 * TODO: reentrancy checks
 * TODO: enable flash loans
 */
contract Kitty is ERC20, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    ERC20 public immutable asset;

    InterestModel public immutable interestModel;

    address public immutable treasury;

    uint256 public totalBorrows;

    mapping(address => uint256) public borrows;

    uint256 public borrowIndex = 1e18; // Compound starts with 1e18 too

    uint256 public borrowIndexTimestamp = block.timestamp;

    constructor(
        ERC20 _asset,
        InterestModel _interestModel,
        address _treasury
    )
        ERC20(
            string.concat("Aloe II ", _asset.name()),
            string.concat(_asset.symbol(), "+"),
            18 // TODO decide magnitude of internal bookkeeping
        )
    {
        asset = _asset;
        interestModel = _interestModel;
        treasury = _treasury;
    }

    modifier onlyBorrowAccount() {
        // TODO verify that borrow account comes from official factory and matches this Kitty's props
        _;
    }

    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        require(amount != 0, "Aloe: 0 deposit"); // TODO use real Error

        // Poke
        accrueInterest();

        uint256 inventory = _getInventory();
        shares = _computeShares(totalSupply, amount, inventory);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Pull in tokens from sender
        asset.safeTransferFrom(msg.sender, address(this), amount); // TODO use callback with before/after balance checks to support fee-on-transfer tokens

        // Mint shares
        _mint(msg.sender, shares);
        // TODO emit Deposit event
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount) {
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error
        // TODO make it so that specifying type(uint256).max will withdraw everything

        // Poke
        accrueInterest();

        uint256 inventory = _getInventory();
        amount = FullMath.mulDiv(inventory, shares, totalSupply);
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        // Transfer tokens
        asset.safeTransfer(msg.sender, amount); // will fail if `asset.balanceOf(address(this)) < amount`

        // Burn shares
        _burn(msg.sender, shares);
        // TODO emit Withdraw event
    }

    function borrow(uint256 amount) external onlyBorrowAccount {
        accrueInterest();

        borrows[msg.sender] += FullMath.mulDiv(1e18, amount, borrowIndex);
        totalBorrows += amount;

        asset.safeTransfer(msg.sender, amount);
    }

    function repay(uint256 amount) external onlyBorrowAccount {
        accrueInterest();

        borrows[msg.sender] -= FullMath.mulDiv(1e18, amount, borrowIndex); // will fail if `amount / borrowIndex > borrows[msg.sender`
        totalBorrows -= amount;

        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function accrueInterest() public {
        uint256 inventory = _getInventory();

        uint256 accrualFactor = interestModel.getAccrualFactor(
            block.timestamp - borrowIndexTimestamp,
            FullMath.mulDiv(1e8, totalBorrows, inventory)
        );

        uint256 accruedInterest = FullMath.mulDiv(totalBorrows, accrualFactor, 1e8);
        totalBorrows += accruedInterest;
        inventory += accruedInterest;
        // borrowIndex += FullMath.mulDiv(borrowIndex, accrualFactor, 1e8); // 2 reads, 1 write
        borrowIndex = FullMath.mulDiv(borrowIndex, 1e8 + accrualFactor, 1e8); // 1 read, 1 write
        borrowIndexTimestamp = block.timestamp;

        uint256 newTotalSupply = FullMath.mulDiv(
            totalSupply,
            inventory,
            inventory - accruedInterest / 8 // `8` indicates a 12.5% reserve factor
        );
        _mint(treasury, newTotalSupply - totalSupply);
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    // TODO use ERC4626-style function names
    function balanceOfUnderlying(address account) external view returns (uint256) {
        // TODO this should probably accrueInterest
        return FullMath.mulDiv(_getInventory(), balanceOf[account], totalSupply);
    }

    function borrowBalanceCurrent(address account) external view returns (uint256) {
        return FullMath.mulDiv(borrows[account], borrowIndex, 1e18);
    }

    function _getInventory() private view returns (uint256) {
        return asset.balanceOf(address(this)) + totalBorrows;
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _computeShares(
        uint256 _totalSupply,
        uint256 _inventory,
        uint256 _amount
    ) private pure returns (uint256) {
        // TODO When _totalSupply == 0, require that _amount > someValue to avoid math errors
        return (_totalSupply == 0) ? _amount : FullMath.mulDiv(_amount, _totalSupply, _inventory);
    }
}

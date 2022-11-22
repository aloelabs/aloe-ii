// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {FullMath} from "./libraries/FullMath.sol";

import {ERC20, InterestModel, LenderERC20} from "./LenderERC20.sol";

contract LenderERC4626 is LenderERC20 {
    using FullMath for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor(address treasury, InterestModel interestModel) LenderERC20(treasury, interestModel) {

    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        (, uint256 inventory, ) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return inventory;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return _convertToShares(assets, inventory, newTotalSupply);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return _convertToAssets(shares, inventory, newTotalSupply);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return (newTotalSupply == 0) ? shares : shares.mulDivRoundingUp(inventory, newTotalSupply);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return (newTotalSupply == 0) ? assets : assets.mulDivRoundingUp(newTotalSupply, inventory);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a conservative estimate of the maximum amount of `asset()` that can be deposited into the
     * Vault for `receiver`, through a deposit call.
     * @return The maximum amount of `asset()` that can be deposited
     *
     * @dev Should return the *precise* maximum. In this case that'd be on the order of 2**112 with weird constraints
     * coming from both `lastBalance` and `totalSupply`, which changes during interest accrual. Instead of doing
     * complicated math, we provide a constant conservative estimate of 2**96.
     *
     * - MUST return a limited value if receiver is subject to some deposit limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
     * - MUST NOT revert.
     */
    function maxDeposit(address) external pure returns (uint256) {
        return 1 << 96;
    }

    /**
     * @notice Returns a conservative estimate of the maximum number of Vault shares that can be minted for `receiver`,
     * through a mint call.
     * @return The maximum number of Vault shares that can be minted
     *
     * @dev Should return the *precise* maximum. In this case that'd be on the order of 2**112 with weird constraints
     * coming from both `lastBalance` and `totalSupply`, which changes during interest accrual. Instead of doing
     * complicated math, we provide a constant conservative estimate of 2**96.
     * 
     * - MUST return a limited value if receiver is subject to some mint limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum number of shares that may be minted.
     * - MUST NOT revert.
     */
    function maxMint(address) external pure returns (uint256) {
        return 1 << 96;
    }

    /**
     * @notice Returns the maximum amount of `asset()` that can be withdrawn from the Vault by `owner`, through a
     * withdraw call.
     * @param owner The address that would burn Vault shares when withdrawing
     * @return The maximum amount of `asset()` that can be withdrawn
     *
     * @dev
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxWithdraw(address owner) external view returns (uint256) {
        uint256 a = convertToAssets(balanceOf[owner]);
        uint256 b = asset().balanceOf(address(this));
        return a < b ? a : b;
    }

    /**
     * @notice Returns the maximum number of Vault shares that can be redeemed in the Vault by `owner`, through a
     * redeem call.
     * @param owner The address that would burn Vault shares when redeeming
     * @return The maximum number of Vault shares that can be redeemed
     *
     * @dev
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST return balanceOf(owner) if owner is not subject to any withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxRedeem(address owner) external view returns (uint256) {
        uint256 a = balanceOf[owner];
        uint256 b = convertToShares(asset().balanceOf(address(this)));
        return a < b ? a : b;
    }
}

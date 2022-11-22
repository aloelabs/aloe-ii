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
}

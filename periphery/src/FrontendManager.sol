// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";
import {Lender} from "aloe-ii-core/Lender.sol";

contract FrontendManager is IManager {
    using SafeTransferLib for ERC20;

    Factory public immutable FACTORY;

    constructor(Factory _factory) {
        FACTORY = _factory;
    }

    /* solhint-disable code-complexity */

    // TODO this is an external function that does lots of different stuff. be extra sure that it's not a security risk,
    // especially given that frontend users will be approving it to spend their tokens.
    function callback(bytes calldata data) external returns (uint144 positions) {
        require(FACTORY.isBorrower(msg.sender), "Aloe: bad account");

        Borrower account = Borrower(msg.sender);

        uint8[] memory actions;
        bytes[] memory args;
        (actions, args, positions) = abi.decode(data, (uint8[], bytes[], uint144));

        for (uint256 i; i < actions.length; i++) {
            uint8 action = actions[i];

            // transfer in
            if (action == 0) {
                (address asset, uint256 amount) = abi.decode(args[i], (address, uint256));
                (address owner, ) = account.packedSlot();
                ERC20(asset).safeTransferFrom(owner, msg.sender, amount);
                continue;
            }

            // transfer out
            if (action == 1) {
                (address asset, uint256 amount) = abi.decode(args[i], (address, uint256));
                (address owner, ) = account.packedSlot();
                ERC20(asset).safeTransferFrom(msg.sender, owner, amount);
                continue;
            }

            // borrow
            if (action == 2) {
                (uint256 amount0, uint256 amount1) = abi.decode(args[i], (uint256, uint256));
                account.borrow(amount0, amount1, msg.sender);
                continue;
            }

            // repay
            if (action == 3) {
                (uint256 amount0, uint256 amount1) = abi.decode(args[i], (uint256, uint256));
                account.repay(amount0, amount1);
                continue;
            }

            // add liquidity
            if (action == 4) {
                (int24 lower, int24 upper, uint128 liquidity) = abi.decode(args[i], (int24, int24, uint128));
                account.uniswapDeposit(lower, upper, liquidity);
                continue;
            }

            // remove liquidity
            if (action == 5) {
                (int24 lower, int24 upper, uint128 liquidity) = abi.decode(args[i], (int24, int24, uint128));
                account.uniswapWithdraw(lower, upper, liquidity);
                continue;
            }
        }

        // TODO emit an event that includes the owner and the current uniswap tick
    }

    /* solhint-enable code-complexity */
}

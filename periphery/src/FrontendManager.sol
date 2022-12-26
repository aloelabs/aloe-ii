// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Uniswap} from "aloe-ii-core/libraries/Uniswap.sol";

import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";
import {Lender} from "aloe-ii-core/Lender.sol";

contract FrontendManager is IManager {
    using SafeTransferLib for ERC20;

    Factory public immutable FACTORY;

    Uniswap.Position[] positions;

    constructor(Factory _factory) {
        FACTORY = _factory;
    }

    /* solhint-disable code-complexity */

    // TODO this is an external function that does lots of different stuff. be extra sure that it's not a security risk,
    // especially given that frontend users will be approving it to spend their tokens.
    function callback(bytes calldata data) external returns (Uniswap.Position[] memory, bool) {
        delete positions;

        require(FACTORY.isBorrower(msg.sender), "Aloe: bad account");

        Borrower account = Borrower(msg.sender);
        IUniswapV3Pool pool = account.UNISWAP_POOL();

        (uint8[] memory actions, bytes[] memory args) = abi.decode(data, (uint8[], bytes[]));

        for (uint256 i; i < actions.length; i++) {
            uint8 action = actions[i];

            // transfer in
            if (action == 0) {
                (address asset, uint256 amount) = abi.decode(args[i], (address, uint256));
                ERC20(asset).safeTransferFrom(account.owner(), msg.sender, amount);
                continue;
            }

            // transfer out
            if (action == 1) {
                (address asset, uint256 amount) = abi.decode(args[i], (address, uint256));
                ERC20(asset).safeTransferFrom(msg.sender, account.owner(), amount);
                continue;
            }

            // mint
            if (action == 2) {
                (address lender, uint256 amount) = abi.decode(args[i], (address, uint256));
                ERC20 asset = Lender(lender).asset();

                asset.safeTransferFrom(msg.sender, lender, amount);
                Lender(lender).deposit(amount, msg.sender);

                continue;
            }

            // burn
            if (action == 3) {
                (address lender, uint256 shares) = abi.decode(args[i], (address, uint256));
                Lender(lender).redeem(shares, msg.sender, msg.sender);
                continue;
            }

            // borrow
            if (action == 4) {
                (uint256 amount0, uint256 amount1) = abi.decode(args[i], (uint256, uint256));
                account.borrow(amount0, amount1, msg.sender);
                continue;
            }

            // repay
            if (action == 5) {
                (uint256 amount0, uint256 amount1) = abi.decode(args[i], (uint256, uint256));
                account.repay(amount0, amount1);
                continue;
            }

            // add liquidity
            if (action == 6) {
                (int24 lower, int24 upper, uint128 liquidity) = abi.decode(args[i], (int24, int24, uint128));
                account.uniswapDeposit(lower, upper, liquidity);

                positions.push(Uniswap.Position(lower, upper));
                continue;
            }

            // remove liquidity
            if (action == 7) {
                (int24 lower, int24 upper, uint128 liquidity) = abi.decode(args[i], (int24, int24, uint128));
                account.uniswapWithdraw(lower, upper, liquidity);
                continue;
            }
        }

        Uniswap.Position[] memory oldPositions = account.getUniswapPositions();
        uint256 oldPositionsLen = oldPositions.length;

        for (uint256 i = 0; i < oldPositionsLen; ) {
            Uniswap.Position memory position = oldPositions[i];
            (uint128 liquidity, , , , ) = pool.positions(
                keccak256(abi.encodePacked(msg.sender, position.lower, position.upper))
            );

            if (liquidity != 0) positions.push(position);

            unchecked {
                i++;
            }
        }

        bool includeLenderReceipts = account.LENDER0().balanceOf(msg.sender) != 0 ||
            account.LENDER1().balanceOf(msg.sender) != 0;
        return (positions, includeLenderReceipts);

        // TODO emit an event that includes the owner and the current uniswap tick
    }

    /* solhint-enable code-complexity */
}

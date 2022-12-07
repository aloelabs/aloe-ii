// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import {Uniswap} from "aloe-ii-core/libraries/Uniswap.sol";

import {Lender} from "aloe-ii-core/Lender.sol";
import {Factory} from "aloe-ii-core/Factory.sol";
import {IManager, Borrower} from "aloe-ii-core/Borrower.sol";

contract FrontendManager is IManager, IUniswapV3SwapCallback {
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

                asset.safeTransferFrom(address(account), lender, amount);
                Lender(lender).deposit(amount, address(account));

                continue;
            }

            // burn
            if (action == 3) {
                (address lender, uint256 shares) = abi.decode(args[i], (address, uint256));
                Lender(lender).redeem(shares, address(account), address(account));
                continue;
            }

            // borrow
            if (action == 4) {
                (uint256 amount0, uint256 amount1) = abi.decode(args[i], (uint256, uint256));
                account.borrow(amount0, amount1, address(account));
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

            // swap
            if (action == 8) {
                (bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) = abi.decode(
                    args[i],
                    (bool, int256, uint160)
                );
                pool.swap(msg.sender, zeroForOne, amountSpecified, sqrtPriceLimitX96, abi.encode(address(account)));
                continue;
            }
        }

        Uniswap.Position[] memory oldPositions = account.getUniswapPositions();

        for (uint256 i = 0; i < oldPositions.length; i++) {
            Uniswap.Position memory position = oldPositions[i];
            (uint128 liquidity, , , , ) = pool.positions(
                keccak256(abi.encodePacked(msg.sender, position.lower, position.upper))
            );

            if (liquidity != 0) positions.push(position);
        }

        bool includeLenderReceipts = account.LENDER0().balanceOf(address(account)) != 0 ||
            account.LENDER1().balanceOf(address(account)) != 0;
        return (positions, includeLenderReceipts);
    }

    /* solhint-enable code-complexity */

    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        address borrower = abi.decode(data, (address));

        if (amount0Delta > 0) {
            ERC20 token0 = ERC20(IUniswapV3Pool(msg.sender).token0());
            token0.safeTransferFrom(borrower, msg.sender, uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            ERC20 token1 = ERC20(IUniswapV3Pool(msg.sender).token1());
            token1.safeTransferFrom(borrower, msg.sender, uint256(amount1Delta));
        }
    }

    function _approve(address token, address spender, uint256 amount) private {
        // 200 gas to read uint256
        if (ERC20(token).allowance(address(this), spender) < amount) {
            // 20000 gas to write uint256 if changing from zero to non-zero
            // 5000  gas to write uint256 if changing from non-zero to non-zero
            ERC20(token).safeApprove(spender, type(uint256).max);
        }
    }
}

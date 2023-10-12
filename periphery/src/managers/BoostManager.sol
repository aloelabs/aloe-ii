// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IUniswapV3SwapCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import {zip} from "aloe-ii-core/libraries/Positions.sol";
import {TickMath} from "aloe-ii-core/libraries/TickMath.sol";
import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";
import {Lender} from "aloe-ii-core/Lender.sol";

import {INonfungiblePositionManager as IUniswapNFT} from "../interfaces/INonfungiblePositionManager.sol";

contract BoostManager is IManager, IUniswapV3SwapCallback {
    using SafeTransferLib for ERC20;

    Factory public immutable FACTORY;

    address public immutable BOOST_NFT;

    IUniswapNFT public immutable UNISWAP_NFT;

    constructor(Factory factory, address boostNft, IUniswapNFT uniswapNft) {
        FACTORY = factory;
        BOOST_NFT = boostNft;
        UNISWAP_NFT = uniswapNft;
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) external {
        Borrower borrower = abi.decode(data, (Borrower));
        borrower.transfer(amount0 > 0 ? uint256(amount0) : 0, amount1 > 0 ? uint256(amount1) : 0, msg.sender);
    }

    function callback(bytes calldata data, address owner, uint208) external override returns (uint208) {
        // We cast `msg.sender` as a `Borrower`, but it could really be anything. DO NOT TRUST!
        Borrower borrower = Borrower(payable(msg.sender));

        // Need to check that `msg.sender` is really a borrower and that its owner is `BOOST_NFT`
        // in order to be sure that incoming `data` is in the expected format
        require(FACTORY.isBorrower(msg.sender) && owner == BOOST_NFT, "Aloe: bad caller");

        // Now `owner` is the true owner of the borrower
        uint8 action;
        bytes memory args;
        (owner, action, args) = abi.decode(data, (address, uint8, bytes));

        // Mint Boost NFT (import funds from Uniswap NFT)
        if (action == 0) {
            // The ID of the Uniswap NFT to import
            uint256 tokenId;
            // The position's lower tick
            int24 lower;
            // The position's upper tick
            int24 upper;
            // Amount of liquidity in the position
            uint128 liquidity;
            // Leverage factor
            uint24 boost;
            (tokenId, lower, upper, liquidity, boost) = abi.decode(args, (uint256, int24, int24, uint128, uint24));

            require(owner == UNISWAP_NFT.ownerOf(tokenId), "Aloe: owners must match to import");

            unchecked {
                (uint256 amount0, uint256 amount1) = _withdrawFromUniswapNFT(tokenId, liquidity, msg.sender);
                // Add 0.1% extra to account for rounding in Uniswap's math. This is more gas-efficient than
                // computing exact amounts needed with LiquidityAmounts library, and has negligible impact on
                // interest rates and liquidation thresholds.
                borrower.borrow((amount0 * (boost - 9990)) / 10000, (amount1 * (boost - 9990)) / 10000, msg.sender);
                borrower.uniswapDeposit(lower, upper, uint128((uint256(liquidity) * boost) / 10000));
            }

            return zip([lower, upper, 0, 0, 0, 0]);
        }

        // Collect earned fees
        if (action == 1) {
            // The position's lower and upper ticks
            (int24 lower, int24 upper) = abi.decode(args, (int24, int24));
            borrower.uniswapWithdraw(lower, upper, 0, owner);
        }

        // Burn liquidity
        if (action == 2) {
            // The position's lower tick
            int24 lower;
            // The position's upper tick
            int24 upper;
            // Amount of liquidity in the position
            uint128 liquidity;
            // Maximum amount of token0 or token1 to swap in order to repay debts
            uint128 maxSpend;
            // Whether to swap token0 for token1 or vice versa
            bool zeroForOne;
            (lower, upper, liquidity, maxSpend, zeroForOne) = abi.decode(args, (int24, int24, uint128, uint128, bool));

            // Burn liquidity and collect fees
            borrower.uniswapWithdraw(lower, upper, liquidity, msg.sender);

            // Collect metadata from `borrower`
            Lender lender0 = borrower.LENDER0();
            Lender lender1 = borrower.LENDER1();
            ERC20 token0 = borrower.TOKEN0();
            ERC20 token1 = borrower.TOKEN1();

            // Balance sheet computations
            lender0.accrueInterest();
            lender1.accrueInterest();
            uint256 liabilities0 = lender0.borrowBalanceStored(msg.sender);
            uint256 liabilities1 = lender1.borrowBalanceStored(msg.sender);
            uint256 assets0 = token0.balanceOf(msg.sender);
            uint256 assets1 = token1.balanceOf(msg.sender);
            int256 surplus0 = int256(assets0) - int256(liabilities0);
            int256 surplus1 = int256(assets1) - int256(liabilities1);

            // Swap iff (it's necessary) AND (direction matches user's intent)
            if (surplus0 < 0 && !zeroForOne) {
                (, int256 spent1) = borrower.UNISWAP_POOL().swap({
                    recipient: msg.sender,
                    zeroForOne: false,
                    amountSpecified: surplus0, // negative implies "exact amount out"
                    sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1,
                    data: abi.encode(borrower, token0, token1)
                });
                require(uint256(spent1) <= maxSpend, "slippage");
                assets0 = liabilities0;
                assets1 -= uint256(spent1);
            } else if (surplus1 < 0 && zeroForOne) {
                (int256 spent0, ) = borrower.UNISWAP_POOL().swap({
                    recipient: msg.sender,
                    zeroForOne: true,
                    amountSpecified: surplus1, // negative implies "exact amount out"
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1,
                    data: abi.encode(borrower, token0, token1)
                });
                require(uint256(spent0) <= maxSpend, "slippage");
                assets0 -= uint256(spent0);
                assets1 = liabilities1;
            }

            // Repay
            borrower.repay(liabilities0, liabilities1);

            unchecked {
                borrower.transfer(assets0 - liabilities0, assets1 - liabilities1, owner);
                borrower.withdrawAnte(payable(owner));
            }
        }

        return 0;
    }

    function _withdrawFromUniswapNFT(
        uint256 tokenId,
        uint128 liquidity,
        address recipient
    ) private returns (uint256 burned0, uint256 burned1) {
        (burned0, burned1) = UNISWAP_NFT.decreaseLiquidity(
            IUniswapNFT.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        UNISWAP_NFT.collect(
            IUniswapNFT.CollectParams({
                tokenId: tokenId,
                recipient: recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }
}

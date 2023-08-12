// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {zip} from "aloe-ii-core/libraries/Positions.sol";
import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";
import {Lender} from "aloe-ii-core/Lender.sol";

import {INonfungiblePositionManager as IUniswapNFT} from "../interfaces/INonfungiblePositionManager.sol";

contract BoostManager is IManager {
    using SafeTransferLib for ERC20;

    Factory public immutable FACTORY;

    address public immutable BOOST_NFT;

    IUniswapNFT public immutable UNISWAP_NFT;

    constructor(Factory factory, address boostNft, IUniswapNFT uniswapNft) {
        FACTORY = factory;
        BOOST_NFT = boostNft;
        UNISWAP_NFT = uniswapNft;
    }

    function callback(bytes calldata data) external override returns (uint144) {
        // We cast `msg.sender` as a `Borrower`, but it could really be anything. DO NOT TRUST!
        Borrower borrower = Borrower(msg.sender);
        // Same goes for `owner` -- we don't yet know if it's really the owner
        (address owner, , ) = borrower.slot0();

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
                (uint256 amount0, uint256 amount1) = _withdrawFromNFT(tokenId, liquidity, msg.sender);
                // Add 0.1% extra to account for rounding in Uniswap's math. This is more gas-efficient than
                // computing exact amounts needed with LiquidityAmounts library, and has negligible impact on
                // interest rates and liquidation thresholds.
                borrower.borrow(amount0 * (boost + 10) / 10000, amount1 * (boost + 10) / 10000, msg.sender);
                borrower.uniswapDeposit(lower, upper, uint128(uint256(liquidity) * boost / 10000));
            }

            return zip([lower, upper, 0, 0, 0, 0]);
        }

        // Burn liquidity
        if (action == 1) {
            // The position's lower tick
            int24 lower;
            // The position's upper tick
            int24 upper;
            // Amount of liquidity in the position
            uint128 liquidity;
            (lower, upper, liquidity) = abi.decode(args, (int24, int24, uint128));

            Lender lender0 = borrower.LENDER0();
            Lender lender1 = borrower.LENDER1();
            lender0.accrueInterest();
            lender1.accrueInterest();
            uint256 amount0 = lender0.borrowBalanceStored(msg.sender);
            uint256 amount1 = lender1.borrowBalanceStored(msg.sender);

            borrower.uniswapWithdraw(lower, upper, uint128(liquidity));
            borrower.repay(amount0, amount1);

            ERC20 token0 = borrower.TOKEN0();
            ERC20 token1 = borrower.TOKEN1();
            amount0 = token0.balanceOf(msg.sender);
            amount1 = token1.balanceOf(msg.sender);

            token0.safeTransferFrom(msg.sender, owner, amount0);
            token1.safeTransferFrom(msg.sender, owner, amount1);

            return 0;
        }

        return 0;
    }

    function _withdrawFromNFT(
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

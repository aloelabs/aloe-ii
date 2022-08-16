// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "src/libraries/Uniswap.sol";

contract UniswapTest is Test {
    using Uniswap for Uniswap.Position;

    IUniswapV3Pool constant UNISWAP_POOL = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    address constant POSITION_OWNER = 0x33cB657E7fd57F1f2d5f392FB78D5FA80806d1B4;
    Uniswap.Position position;

    function setUp() public {
        position = Uniswap.Position(187540, 215270);
    }

    function test_fees() public {
        (, int24 currentTick, , , , , ) = UNISWAP_POOL.slot0();
        Uniswap.PositionInfo memory positionInfoA;
        (
            positionInfoA.liquidity,
            positionInfoA.feeGrowthInside0LastX128,
            positionInfoA.feeGrowthInside1LastX128,
            positionInfoA.tokensOwed0,
            positionInfoA.tokensOwed1
        ) = UNISWAP_POOL.positions(keccak256(abi.encodePacked(POSITION_OWNER, position.lower, position.upper)));

        // library function (view-only)
        (uint256 fees0, uint256 fees1) = position.fees(
            UNISWAP_POOL,
            positionInfoA,
            currentTick,
            UNISWAP_POOL.feeGrowthGlobal0X128(),
            UNISWAP_POOL.feeGrowthGlobal1X128()
        );

        // poke (state-changing)
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.lower, position.upper, 0);
        Uniswap.PositionInfo memory positionInfoB;
        (
            positionInfoB.liquidity,
            positionInfoB.feeGrowthInside0LastX128,
            positionInfoB.feeGrowthInside1LastX128,
            positionInfoB.tokensOwed0,
            positionInfoB.tokensOwed1
        ) = UNISWAP_POOL.positions(keccak256(abi.encodePacked(POSITION_OWNER, position.lower, position.upper)));

        assert(fees0 == positionInfoB.tokensOwed0);
        assert(fees1 == positionInfoB.tokensOwed1);
    }

    function test_gas_getAmountsWithView() public {
        Uniswap.PositionInfo memory positionInfo;
        (
            positionInfo.liquidity,
            positionInfo.feeGrowthInside0LastX128,
            positionInfo.feeGrowthInside1LastX128,
            positionInfo.tokensOwed0,
            positionInfo.tokensOwed1
        ) = UNISWAP_POOL.positions(keccak256(abi.encodePacked(POSITION_OWNER, position.lower, position.upper)));

        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = UNISWAP_POOL.slot0();
        (uint256 fees0, uint256 fees1) = position.fees(
            UNISWAP_POOL,
            positionInfo,
            currentTick,
            UNISWAP_POOL.feeGrowthGlobal0X128(),
            UNISWAP_POOL.feeGrowthGlobal1X128()
        );
        (uint256 principle0, uint256 principle1) = position.amountsForLiquidity(sqrtPriceX96, positionInfo.liquidity);

        console.log(principle0 + fees0);
        console.log(principle1 + fees1);
    }

    function test_gas_getAmountsWithPoke() public {
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.lower, position.upper, 0);

        (uint128 liquidity, , , uint256 fees0, uint256 fees1) = UNISWAP_POOL.positions(
            keccak256(abi.encodePacked(POSITION_OWNER, position.lower, position.upper))
        );

        (uint160 sqrtPriceX96, , , , , , ) = UNISWAP_POOL.slot0();
        (uint256 principle0, uint256 principle1) = position.amountsForLiquidity(sqrtPriceX96, liquidity);

        console.log(principle0 + fees0);
        console.log(principle1 + fees1);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "src/libraries/Uniswap.sol";

contract UniswapTest is Test {
    using Uniswap for Uniswap.Position;

    IUniswapV3Pool constant UNISWAP_POOL = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    address constant POSITION_OWNER = 0x33cB657E7fd57F1f2d5f392FB78D5FA80806d1B4;
    Uniswap.Position position;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.rollFork(15_348_451);

        position = Uniswap.Position(187540, 215270);
    }

    function test_burnBehaviour() public {
        Uniswap.PositionInfo memory positionInfo = position.info(UNISWAP_POOL, POSITION_OWNER);

        vm.expectRevert(bytes("LS"));
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.lower - 1, position.upper, positionInfo.liquidity);

        vm.expectRevert(bytes("TLU"));
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.upper, position.lower, positionInfo.liquidity);

        // Should be able to burn all liquidity, obviously
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.lower, position.upper, positionInfo.liquidity);

        // All liquidity is gone now, so we shouldn't be able to burn it again
        vm.expectRevert(bytes("LS"));
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.lower, position.upper, positionInfo.liquidity);

        // Uniswap won't even allow us to poke the position if it has 0 liquidity
        vm.expectRevert(bytes("NP"));
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.lower, position.upper, 0);

        // But checking info should still work
        position.info(UNISWAP_POOL, POSITION_OWNER);

        // And collecting should work
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.collect(address(this), position.lower, position.upper, type(uint128).max, type(uint128).max);

        // Again
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.collect(address(this), position.lower, position.upper, type(uint128).max, type(uint128).max);

        position.lower = position.upper + 123;
        positionInfo = position.info(UNISWAP_POOL, POSITION_OWNER);
        assertEq(positionInfo.liquidity, 0);
    }

    function test_fees() public {
        (, int24 currentTick, , , , , ) = UNISWAP_POOL.slot0();
        Uniswap.PositionInfo memory positionInfoA = position.info(UNISWAP_POOL, POSITION_OWNER);

        // library function (view-only)
        (uint256 fees0, uint256 fees1) = position.fees(
            UNISWAP_POOL,
            positionInfoA,
            Uniswap.FeeComputationCache(
                currentTick,
                UNISWAP_POOL.feeGrowthGlobal0X128(),
                UNISWAP_POOL.feeGrowthGlobal1X128()
            )
        );

        // poke (state-changing)
        vm.prank(POSITION_OWNER);
        UNISWAP_POOL.burn(position.lower, position.upper, 0);
        Uniswap.PositionInfo memory positionInfoB = position.info(UNISWAP_POOL, POSITION_OWNER);

        assertEq(fees0, positionInfoB.tokensOwed0);
        assertEq(fees1, positionInfoB.tokensOwed1);
    }

    function test_gas_getAmountsWithView() public view {
        Uniswap.PositionInfo memory positionInfo = position.info(UNISWAP_POOL, POSITION_OWNER);

        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = UNISWAP_POOL.slot0();
        (uint256 fees0, uint256 fees1) = position.fees(
            UNISWAP_POOL,
            positionInfo,
            Uniswap.FeeComputationCache(
                currentTick,
                UNISWAP_POOL.feeGrowthGlobal0X128(),
                UNISWAP_POOL.feeGrowthGlobal1X128()
            )
        );
        (uint256 principle0, uint256 principle1) = position.amountsForLiquidity(sqrtPriceX96, positionInfo.liquidity);

        console.log(principle0 + fees0);
        console.log(principle1 + fees1);
    }

    function test_gas_getAmountsWithPoke() public {
        vm.pauseGasMetering();
        vm.prank(POSITION_OWNER);
        vm.resumeGasMetering();
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

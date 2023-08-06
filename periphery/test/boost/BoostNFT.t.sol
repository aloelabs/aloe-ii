// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;

import "forge-std/Test.sol";

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {BoostNFT, Borrower, Factory, IManager, IUniswapV3Pool} from "src/boost/BoostNFT.sol";
import {INonfungiblePositionManager as IUniswapNFT} from "src/interfaces/INonfungiblePositionManager.sol";
import {BoostManager, Lender} from "src/managers/BoostManager.sol";

Factory constant FACTORY = Factory(0x95110C9806833d3D3C250112fac73c5A6f631E80);

IUniswapNFT constant UNISWAP_NFT = IUniswapNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

/// @title Describes NFT token positions
/// @notice Produces a string containing the data URI for a JSON metadata string
contract BoostNFTTest is Test {
    event CreateBorrower(IUniswapV3Pool indexed pool, address indexed owner, address account);

    BoostNFT private boostNft;

    BoostManager private boostManager;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.rollFork(107847552);

        boostNft = new BoostNFT(FACTORY);
        boostManager = new BoostManager(FACTORY, address(boostNft), UNISWAP_NFT);

        boostNft.setBoostManager(boostManager);
    }

    function test_setOwner(address newOwner) public {
        vm.assume(newOwner != address(this));

        vm.prank(newOwner);
        vm.expectRevert(bytes(""));
        boostNft.setOwner(newOwner);

        boostNft.setOwner(newOwner);
        assertEq(boostNft.owner(), newOwner);
    }

    function test_setBoostManager(address caller, IManager newBoostManager) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        vm.expectRevert(bytes(""));
        boostNft.setBoostManager(newBoostManager);

        boostNft.setBoostManager(newBoostManager);
        assertEq(address(boostNft.boostManager()), address(newBoostManager));
    }

    function test_createBorrower() public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9);

        vm.expectEmit(true, true, false, false, address(FACTORY));
        emit CreateBorrower(pool, address(boostNft), address(0));
        boostNft.createBorrower(pool);
    }

    function test_mintPermissions() public {
        IUniswapV3Pool pool = IUniswapV3Pool(0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6);

        _prepareLenders(pool);

        uint256 tokenId = 411475;
        int24 lower = -887272;
        int24 upper = 887272;
        uint128 liquidity = 100038005272;
        uint8 boost = 1;
        bytes memory data = abi.encode(tokenId, lower, upper, liquidity, boost);

        vm.expectRevert(bytes("Aloe: owners must match to import"));
        boostNft.mint(pool, data);

        vm.prank(UNISWAP_NFT.ownerOf(tokenId));
        UNISWAP_NFT.approve(address(boostManager), tokenId);

        vm.expectRevert(bytes("Aloe: owners must match to import"));
        boostNft.mint{value: 0.001 ether + 1}(pool, data);

        vm.prank(UNISWAP_NFT.ownerOf(tokenId));
        boostNft.mint{value: 0.001 ether + 1}(pool, data);
    }

    function test_mintStorage() public {
        (address owner, , , ) = _mintX(2);

        uint256 id = uint256(keccak256(abi.encodePacked(owner, uint256(0))));
        assertEq(boostNft.ownerOf(id), owner);
        assertEq(boostNft.balanceOf(owner), 1);
        (Borrower borrower, bool isGeneralized) = boostNft.attributesOf(id);
        assertTrue(FACTORY.isBorrower(address(borrower)));
        assertFalse(isGeneralized);
    }

    function test_gas_mint1x() public {
        _mintX(1);
    }

    function test_gas_mint2x() public {
        _mintX(2);
    }

    function test_gas_mint3x() public {
        _mintX(3);
    }

    function test_gas_mint5x() public {
        _mintX(5);
    }

    function test_remove() public {
        vm.pauseGasMetering();

        (address owner, int24 lower, int24 upper, uint128 liquidity) = _mintX(2);
        uint256 id = uint256(keccak256(abi.encodePacked(owner, uint256(0))));
        bytes memory data = abi.encode(lower, upper, liquidity * 2);

        vm.resumeGasMetering();

        vm.prank(owner);
        boostNft.modify(id, 1, data, [true, true]);
    }

    function _mintX(uint8 boost) private returns (address owner, int24 lower, int24 upper, uint128 liquidity) {
        vm.pauseGasMetering();
        IUniswapV3Pool pool = IUniswapV3Pool(0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6);
        _prepareLenders(pool);

        uint256 tokenId = 411475;
        (, , , , , lower, upper, liquidity, , , , ) = UNISWAP_NFT.positions(tokenId);
        bytes memory data = abi.encode(tokenId, lower, upper, liquidity, boost);

        owner = UNISWAP_NFT.ownerOf(tokenId);

        vm.prank(owner);
        UNISWAP_NFT.approve(address(boostManager), tokenId);
        vm.resumeGasMetering();

        vm.prank(owner);
        boostNft.mint{value: 0.001 ether + 1}(pool, data);
    }

    function _prepareLenders(IUniswapV3Pool pool) private {
        (Lender lender0, Lender lender1, ) = FACTORY.getMarket(pool);
        ERC20 token0 = lender0.asset();
        ERC20 token1 = lender1.asset();

        deal(address(token0), address(lender0), 1000e18 + lender0.lastBalance());
        deal(address(token1), address(lender1), 1000e18 + lender1.lastBalance());

        lender0.deposit(1000e18, address(0));
        lender1.deposit(1000e18, address(0));
    }
}

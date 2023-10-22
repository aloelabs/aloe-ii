// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";
import {Factory, BorrowerDeployer} from "aloe-ii-core/Factory.sol";
import {RateModel} from "aloe-ii-core/RateModel.sol";
import {VolatilityOracle} from "aloe-ii-core/VolatilityOracle.sol";

import {BorrowerNFT} from "src/borrower-nft/BorrowerNFT.sol";

contract NoOp is IManager {
    function callback(bytes calldata, address, uint208) external pure override returns (uint208) {
        return 0;
    }
}

contract BorrowerNFTTest is Test, IManager {
    event CreateBorrower(IUniswapV3Pool indexed pool, address indexed owner, Borrower account);

    IUniswapV3Pool POOL = IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9);

    BorrowerNFT borrowerNft;

    IManager noOpManager;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.rollFork(107847552);

        RateModel rateModel = new RateModel();
        VolatilityOracle oracle = new VolatilityOracle();
        BorrowerDeployer deployer = new BorrowerDeployer();
        Factory factory = new Factory(address(0), address(0), oracle, deployer, rateModel);
        factory.createMarket(POOL);

        borrowerNft = new BorrowerNFT(factory);
        noOpManager = new NoOp();
    }

    function callback(bytes calldata data, address owner, uint208) external override returns (uint208) {
        assertEq(owner, address(borrowerNft));
        assertEq(address(bytes20(data[:20])), address(this));
        return 0;
    }

    function test_mint0Fails() public {
        IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](0);
        bytes12[] memory salts = new bytes12[](0);

        vm.expectRevert(bytes("BAD_QUANTITY"));
        borrowerNft.mint(address(this), pools, salts);
    }

    function test_mint1CreatesBorrower() public {
        IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](1);
        pools[0] = POOL;
        bytes12[] memory salts = new bytes12[](1);
        salts[0] = bytes12(0);

        vm.expectEmit(true, true, false, true);
        emit CreateBorrower(POOL, address(borrowerNft), Borrower(payable(0xBC4D33151DA2813017E84728a07BAd933D319217)));
        borrowerNft.mint(address(this), pools, salts);
    }

    function test_mint2WithSameSaltReverts() public {
        IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](2);
        pools[0] = POOL;
        pools[1] = POOL;
        bytes12[] memory salts = new bytes12[](2);
        salts[0] = bytes12(0);
        salts[1] = bytes12(0);

        vm.expectRevert(0xebfef188);
        borrowerNft.mint(address(this), pools, salts);
    }

    function test_modifyDoesPrependOwnerToData(bytes memory data) public {
        _test_gas_mint(1);

        uint16[] memory indices = new uint16[](1);
        IManager[] memory managers = new IManager[](1);
        bytes[] memory datas = new bytes[](1);
        uint16[] memory antes = new uint16[](1);
        indices[0] = 0;
        managers[0] = this;
        datas[0] = data;
        antes[0] = 0;

        borrowerNft.modify(address(this), indices, managers, datas, antes);
    }

    function test_modifyAuthorization(address nonOwner, bytes memory data) public {
        vm.assume(nonOwner != address(this));

        _test_gas_mint(2);

        uint16[] memory indices = new uint16[](1);
        IManager[] memory managers = new IManager[](1);
        bytes[] memory datas = new bytes[](1);
        uint16[] memory antes = new uint16[](1);
        indices[0] = 0;
        managers[0] = this;
        datas[0] = data;
        antes[0] = 0;

        // Approve `nonOwner` to manage the first Borrower, but not the second
        uint256 tokenId = borrowerNft.tokenOfOwnerByIndex(address(this), 0);
        borrowerNft.approve(nonOwner, tokenId);

        // Should succeed for the one we approved
        vm.prank(nonOwner);
        borrowerNft.modify(address(this), indices, managers, datas, antes);

        // Should fail for the other one
        indices[0] = 1;
        vm.prank(nonOwner);
        vm.expectRevert(bytes("NOT_AUTHORIZED"));
        borrowerNft.modify(address(this), indices, managers, datas, antes);

        // Approve `nonOwner` to manage all Borrowers
        borrowerNft.setApprovalForAll(nonOwner, true);

        // Should succeed for both
        indices[0] = 0;
        vm.prank(nonOwner);
        borrowerNft.modify(address(this), indices, managers, datas, antes);
        indices[0] = 1;
        vm.prank(nonOwner);
        borrowerNft.modify(address(this), indices, managers, datas, antes);
    }

    /*//////////////////////////////////////////////////////////////
                                  GAS
    //////////////////////////////////////////////////////////////*/

    function test_gas_mint1() public {
        _test_gas_mint(1);
    }

    function test_gas_mint2() public {
        _test_gas_mint(2);
    }

    function test_gas_mint4() public {
        _test_gas_mint(4);
    }

    function _test_gas_mint(uint256 n) private {
        vm.pauseGasMetering();
        IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](n);
        bytes12[] memory salts = new bytes12[](n);
        for (uint256 i; i < n; i++) {
            pools[i] = POOL;
            salts[i] = bytes12(uint96(i));
        }
        vm.resumeGasMetering();

        borrowerNft.mint(address(this), pools, salts);
    }

    function test_gas_modify1of1() public {
        _test_gas_modifyKOfN(1, 1);
    }

    function test_gas_modify1of32() public {
        _test_gas_modifyKOfN(1, 32);
    }

    function test_gas_modify4of32() public {
        _test_gas_modifyKOfN(4, 32);
    }

    function _test_gas_modifyKOfN(uint256 k, uint256 n) private {
        vm.pauseGasMetering();
        // Generate calldata for `mint`
        {
            IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](n);
            bytes12[] memory salts = new bytes12[](n);
            for (uint256 i; i < n; i++) {
                pools[i] = POOL;
                salts[i] = bytes12(uint96(i));
            }

            borrowerNft.mint(address(this), pools, salts);
        }

        // Generate calldata for `modify`
        uint16[] memory indices = new uint16[](k);
        IManager[] memory managers = new IManager[](k);
        bytes[] memory datas = new bytes[](k);
        uint16[] memory antes = new uint16[](k);

        for (uint16 i; i < k; i++) {
            indices[i] = i;
            managers[i] = noOpManager;
            datas[i] = "";
            antes[i] = 0;
        }
        vm.resumeGasMetering();

        borrowerNft.modify(address(this), indices, managers, datas, antes);
    }

    function test_gas_mintAndModify1Multicall() public {
        _test_gas_mintAndModifyMulticall(1);
    }

    function test_gas_mintAndModify4Multicall() public {
        _test_gas_mintAndModifyMulticall(4);
    }

    function _test_gas_mintAndModifyMulticall(uint256 n) private {
        bytes[] memory data = new bytes[](2);
        vm.pauseGasMetering();

        // Generate calldata for `mint`
        {
            IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](n);
            bytes12[] memory salts = new bytes12[](n);
            for (uint256 i; i < n; i++) {
                pools[i] = POOL;
                salts[i] = bytes12(uint96(i));
            }

            data[0] = abi.encodeCall(borrowerNft.mint, (address(this), pools, salts));
        }

        // Generate calldata for `modify`
        {
            uint16[] memory indices = new uint16[](n);
            IManager[] memory managers = new IManager[](n);
            bytes[] memory datas = new bytes[](n);
            uint16[] memory antes = new uint16[](n);
            for (uint16 i; i < n; i++) {
                indices[i] = i;
                managers[i] = noOpManager;
                datas[i] = "";
                antes[i] = 0;
            }

            data[1] = abi.encodeCall(borrowerNft.modify, (address(this), indices, managers, datas, antes));
        }

        vm.resumeGasMetering();
        borrowerNft.multicall(data);
    }
}

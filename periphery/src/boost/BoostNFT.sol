// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Borrower, IManager, ERC20} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";

import {NFTDescriptor} from "./NFTDescriptor.sol";
import {SafeERC20Namer} from "./SafeERC20Namer.sol";

contract BoostNFT is ERC721 {
    event ReleaseBorrower(IUniswapV3Pool indexed pool, address indexed owner, address borrower);

    Factory public immutable FACTORY;

    address public governor;

    IManager public boostManager;

    mapping(uint256 => Borrower) public borrowerFor;

    constructor(address governor_, Factory factory) ERC721("Uniswap V3 - Aloe Edition", "UNI-V3-ALOE") {
        governor = governor_;
        FACTORY = factory;
    }

    function setGovernor(address governor_) external {
        require(msg.sender == governor);
        governor = governor_;
    }

    function setBoostManager(IManager boostManager_) external {
        require(msg.sender == governor);
        boostManager = boostManager_;
    }

    function mint(IUniswapV3Pool pool, bytes memory data, uint40 oracleSeed) public payable {
        uint256 id = uint256(keccak256(abi.encodePacked(msg.sender, balanceOf(msg.sender))));

        Borrower borrower = Borrower(FACTORY.createBorrower(pool, address(this)));
        borrowerFor[id] = borrower;
        _mint(msg.sender, id);

        data = abi.encode(msg.sender, 0, data);
        borrower.modify{value: msg.value}(boostManager, data, oracleSeed);
    }

    function modify(uint256 id, uint8 action, bytes memory data, uint40 oracleSeed) external payable {
        require(msg.sender == _ownerOf[id], "Aloe: only NFT owner");

        data = abi.encode(msg.sender, action, data);
        borrowerFor[id].modify{value: msg.value}(boostManager, data, oracleSeed);
    }

    /// @notice Permanently relinquish control of the `Borrower` associated with `id`. The owner can then
    /// manage their Borrower manually.
    function release(uint256 id) external {
        require(msg.sender == _ownerOf[id], "Aloe: only NFT owner");

        Borrower borrower = borrowerFor[id];
        delete borrowerFor[id];
        _burn(id);

        // Give `msg.sender` manual control of their borrower
        borrower.initialize(msg.sender);
        emit ReleaseBorrower(borrower.UNISWAP_POOL(), msg.sender, address(borrower));
    }

    /*//////////////////////////////////////////////////////////////
                            NFT DESCRIPTION
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        Borrower borrower = borrowerFor[id];

        IUniswapV3Pool poolAddress = borrower.UNISWAP_POOL();
        int24[] memory positions = borrower.getUniswapPositions();
        int24 tickLower = positions[0];
        int24 tickUpper = positions[1];
        (, int24 tickCurrent, , , , , ) = poolAddress.slot0();

        ERC20 token0 = borrower.TOKEN0();
        ERC20 token1 = borrower.TOKEN1();
        return
            NFTDescriptor.constructTokenURI(
                NFTDescriptor.ConstructTokenURIParams({
                    tokenId: id,
                    token0: address(token0),
                    token1: address(token1),
                    symbol0: SafeERC20Namer.tokenSymbol(address(token0)),
                    symbol1: SafeERC20Namer.tokenSymbol(address(token1)),
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    tickCurrent: tickCurrent,
                    fee: poolAddress.fee(),
                    poolAddress: address(poolAddress),
                    borrowerAddress: address(borrower),
                    isActive: address(borrower).balance > 0
                })
            );
    }
}

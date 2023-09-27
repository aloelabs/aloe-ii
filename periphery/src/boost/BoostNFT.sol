// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Borrower, IManager, ERC20} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";

import {NFTDescriptor} from "./NFTDescriptor.sol";
import {SafeERC20Namer} from "./SafeERC20Namer.sol";

contract BoostNFT is ERC721 {
    struct NFTAttributes {
        Borrower borrower;
        bool isGeneralized;
    }

    Factory public immutable FACTORY;

    address public owner;

    IManager public boostManager;

    mapping(uint256 => NFTAttributes) public attributesOf;

    Borrower[] internal _freeBorrowers;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address owner_, Factory factory) ERC721("Uniswap V3 - Aloe Edition", "UNI-V3-ALOE") {
        owner = owner_;
        FACTORY = factory;
    }

    /*//////////////////////////////////////////////////////////////
                               GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function setOwner(address owner_) external {
        require(msg.sender == owner);
        owner = owner_;
    }

    function setBoostManager(IManager boostManager_) external {
        require(msg.sender == owner);
        boostManager = boostManager_;
    }

    function createBorrower(IUniswapV3Pool pool) external {
        _freeBorrowers.push(Borrower(FACTORY.createBorrower(pool, address(this))));
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    function mint(IUniswapV3Pool pool, bytes memory initializationData, uint40 oracleSeed) public payable {
        uint256 id = uint256(keccak256(abi.encodePacked(msg.sender, balanceOf(msg.sender))));

        Borrower borrower = _nextBorrower(pool);
        attributesOf[id] = NFTAttributes(borrower, false);
        _mint(msg.sender, id);

        initializationData = abi.encode(msg.sender, 0, initializationData);
        borrower.modify{value: msg.value}(boostManager, initializationData, oracleSeed);
    }

    /*//////////////////////////////////////////////////////////////
                            BORROWER MODIFY
    //////////////////////////////////////////////////////////////*/

    function modify(uint256 id, uint8 action, IManager manager, bytes memory data, uint40 oracleSeed) public payable {
        require(msg.sender == _ownerOf[id], "Aloe: only NFT owner can modify");

        NFTAttributes memory attributes = attributesOf[id];

        if (address(manager) == address(0)) {
            manager = boostManager;
        } else if (!attributes.isGeneralized) {
            attributesOf[id].isGeneralized = true;
        }

        data = abi.encode(msg.sender, action, data);
        attributes.borrower.modify{value: msg.value}(manager, data, oracleSeed);
    }

    function modify(uint256 id, uint8 action, bytes calldata data, uint40 oracleSeed) external payable {
        modify(id, action, IManager(address(0)), data, oracleSeed);
    }

    /*//////////////////////////////////////////////////////////////
                            NFT DESCRIPTION
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        NFTAttributes memory attributes = attributesOf[id];

        int24 tickLower;
        int24 tickUpper;
        int24 tickCurrent;
        int24 tickSpacing;
        IUniswapV3Pool poolAddress = attributes.borrower.UNISWAP_POOL();

        if (!attributes.isGeneralized) {
            int24[] memory positions = attributes.borrower.getUniswapPositions();
            tickLower = positions[0];
            tickUpper = positions[1];
            (, tickCurrent, , , , , ) = poolAddress.slot0();
            tickSpacing = poolAddress.tickSpacing();
        }

        ERC20 token0 = attributes.borrower.TOKEN0();
        ERC20 token1 = attributes.borrower.TOKEN1();
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
                    borrowerAddress: address(attributes.borrower),
                    isGeneralized: attributes.isGeneralized
                })
            );
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _nextBorrower(IUniswapV3Pool pool) private returns (Borrower borrower) {
        unchecked {
            uint256 count = _freeBorrowers.length;
            if (count > 0) {
                borrower = _freeBorrowers[count - 1];
                _freeBorrowers.pop();
            } else {
                borrower = Borrower(FACTORY.createBorrower(pool, address(this)));
            }
        }
    }
}

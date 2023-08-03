// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Borrower, IManager, ERC20} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";

import {INonfungiblePositionManager as INFTManager} from "../interfaces/INonfungiblePositionManager.sol";
import {computePoolAddress} from "../libraries/Uniswap.sol";
import {NFTDescriptor} from "./NFTDescriptor.sol";

contract BoostNFT is ERC721 {
    address public immutable DEPLOYER;

    Factory public immutable FACTORY;

    struct Slot0 {
        IManager boostManager;
        uint256 nextId;
    }

    Slot0 public slot0;

    struct NFTAttributes {
        Borrower borrower;
        bool isGeneralized;
    }

    mapping(uint256 => NFTAttributes) public attributesOf;

    Borrower[] internal freeBorrowers;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(Factory factory) ERC721("Uniswap V3 - Aloe Edition", "UNI-V3-ALOE") {
        DEPLOYER = msg.sender;
        FACTORY = factory;
    }

    /*//////////////////////////////////////////////////////////////
                               GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function setBoostManager(IManager boostManager) external {
        require(msg.sender == DEPLOYER);
        slot0.boostManager = boostManager;
    }

    function createBorrower(IUniswapV3Pool pool) external {
        freeBorrowers.push(Borrower(FACTORY.createBorrower(pool, address(this))));
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    function mint(IUniswapV3Pool pool, bytes memory initializationData) public payable {
        Slot0 memory slot0_ = slot0;

        Borrower borrower = _nextBorrower(pool);
        attributesOf[slot0_.nextId] = NFTAttributes(borrower, false);
        _mint(msg.sender, slot0_.nextId);
        slot0.nextId++;

        initializationData = abi.encode(/* owner */ msg.sender, /* data */ initializationData);
        borrower.modify{value: msg.value}(slot0_.boostManager, initializationData, [false, false]);
    }

    /*//////////////////////////////////////////////////////////////
                            BORROWER MODIFY
    //////////////////////////////////////////////////////////////*/

    function modify(uint256 id, IManager manager, bytes memory data, bool[2] calldata allowances) public payable {
        require(msg.sender == _ownerOf[id], "NOT_AUTHORIZED");

        NFTAttributes memory attributes = attributesOf[id];

        if (address(manager) == address(0)) {
            manager = slot0.boostManager;
        } else if (!attributes.isGeneralized) {
            attributesOf[id].isGeneralized = true;
        }

        data = abi.encode(/* owner */ msg.sender, /* data */ data);
        attributes.borrower.modify{value: msg.value}(manager, data, allowances);
    }

    function modify(uint256 id, bytes calldata data, bool[2] calldata allowances) external payable {
        modify(id, IManager(address(0)), data, allowances);
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
                    symbol0: token0.symbol(),
                    symbol1: token1.symbol(),
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
            uint256 count = freeBorrowers.length;
            if (count > 0) {
                borrower = freeBorrowers[count - 1];
                freeBorrowers.pop();
            } else {
                borrower = Borrower(FACTORY.createBorrower(pool, address(this)));
            }
        }
    }
}

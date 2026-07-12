// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MIPCollection} from "../src/MIPCollection.sol";

contract MIPCollectionTest is Test {
    MIPCollection internal implementation;
    MIPCollection internal collection;
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");

    function setUp() public {
        implementation = new MIPCollection();
        collection = MIPCollection(Clones.clone(address(implementation)));
        collection.initialize(1, creator, "My IP", "MIP", "ipfs://base/");
    }

    function test_initialize_setsCollectionState() public view {
        assertEq(collection.collectionId(), 1);
        assertEq(collection.registry(), address(this));
        assertEq(collection.owner(), creator);
        assertEq(collection.name(), "My IP");
        assertEq(collection.symbol(), "MIP");
        assertEq(collection.collectionBaseUri(), "ipfs://base/");
        assertEq(collection.version(), "1.0.0");
    }

    function test_initialize_cannotRunTwice() public {
        vm.expectRevert();
        collection.initialize(2, alice, "X", "X", "");
    }

    function test_implementation_cannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(1, creator, "X", "X", "");
    }

    function test_initialize_rejectsEmptyNameAndSymbol() public {
        MIPCollection blank = MIPCollection(Clones.clone(address(implementation)));
        vm.expectRevert(MIPCollection.MIPInvalidName.selector);
        blank.initialize(1, creator, "", "MIP", "");
        vm.expectRevert(MIPCollection.MIPInvalidSymbol.selector);
        blank.initialize(1, creator, "My IP", "", "");
    }

    function test_mint_ownerMintsSequentialIdsFromOne() public {
        vm.startPrank(creator);
        uint256 first = collection.mint(alice, "ipfs://token/1", 0);
        uint256 second = collection.mint(alice, "ipfs://token/2", 0);
        vm.stopPrank();
        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(collection.ownerOf(1), alice);
        assertEq(collection.tokenURI(2), "ipfs://token/2");
        assertTrue(collection.tokenExists(1));
        assertFalse(collection.tokenExists(3));
    }

    function test_mint_recordsRegistrationRecord() public {
        vm.warp(1_720_000_000);
        vm.prank(creator);
        collection.mint(alice, "ipfs://token/1", 0);
        assertEq(collection.getTokenCreator(1), creator);
        assertEq(collection.getTokenRegisteredAt(1), 1_720_000_000);
        (address tokenOwner, string memory uri, address originalCreator, uint64 registeredAt) =
            collection.getFullTokenData(1);
        assertEq(tokenOwner, alice);
        assertEq(uri, "ipfs://token/1");
        assertEq(originalCreator, creator);
        assertEq(registeredAt, 1_720_000_000);
    }

    function test_recordViews_revertForNonexistentToken() public {
        vm.expectRevert();
        collection.getTokenCreator(1);
        vm.expectRevert();
        collection.getTokenRegisteredAt(1);
        vm.expectRevert();
        collection.getFullTokenData(1);
    }

    function test_mint_rejectsEmptyUri() public {
        vm.prank(creator);
        vm.expectRevert(MIPCollection.MIPInvalidTokenUri.selector);
        collection.mint(alice, "", 0);
    }

    function test_mint_emitsTokenMinted() public {
        vm.expectEmit(true, true, false, true);
        emit MIPCollection.TokenMinted(1, alice, "ipfs://token/1", 250);
        vm.prank(creator);
        collection.mint(alice, "ipfs://token/1", 250);
    }

    function test_mint_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        collection.mint(alice, "ipfs://token/1", 0);
    }

    function test_mint_toContractWithoutReceiverSucceeds() public {
        address plainContract = address(new NonReceiver());
        vm.prank(creator);
        uint256 id = collection.mint(plainContract, "ipfs://token/1", 0);
        assertEq(collection.ownerOf(id), plainContract);
    }

    function test_transferOwnership_movesMintRight() public {
        vm.prank(creator);
        collection.transferOwnership(alice);
        vm.prank(alice);
        uint256 id = collection.mint(alice, "ipfs://token/1", 0);
        assertEq(id, 1);
        assertEq(collection.getTokenCreator(id), alice);
    }

    function test_renounceOwnership_isDisabled() public {
        vm.prank(creator);
        vm.expectRevert(MIPCollection.MIPRenounceDisabled.selector);
        collection.renounceOwnership();
    }
}

contract NonReceiver {}

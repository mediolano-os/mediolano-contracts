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
        collection.initialize(1, creator, "My IP", "MIP", "ipfs://base/", 500);
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
        collection.initialize(2, alice, "X", "X", "", 0);
    }

    function test_implementation_cannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(1, creator, "X", "X", "", 0);
    }

    function test_mint_ownerMintsSequentialIdsFromOne() public {
        vm.startPrank(creator);
        uint256 first = collection.mint(alice, "ipfs://token/1");
        uint256 second = collection.mint(alice, "ipfs://token/2");
        vm.stopPrank();
        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(collection.ownerOf(1), alice);
        assertEq(collection.tokenURI(2), "ipfs://token/2");
        assertTrue(collection.tokenExists(1));
        assertFalse(collection.tokenExists(3));
    }

    function test_mint_recordsTokenCreator() public {
        vm.prank(creator);
        collection.mint(alice, "ipfs://token/1");
        assertEq(collection.getTokenCreator(1), creator);
    }

    function test_mint_emitsTokenMinted() public {
        vm.expectEmit(true, true, false, true);
        emit MIPCollection.TokenMinted(1, alice, "ipfs://token/1");
        vm.prank(creator);
        collection.mint(alice, "ipfs://token/1");
    }

    function test_mint_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        collection.mint(alice, "ipfs://token/1");
    }

    function test_transferOwnership_movesMintRight() public {
        vm.prank(creator);
        collection.transferOwnership(alice);
        vm.prank(alice);
        uint256 id = collection.mint(alice, "ipfs://token/1");
        assertEq(id, 1);
    }
}

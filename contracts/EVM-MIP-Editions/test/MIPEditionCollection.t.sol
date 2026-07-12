// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MIPEditionCollection} from "../src/MIPEditionCollection.sol";

contract MIPEditionCollectionTest is Test {
    MIPEditionCollection internal implementation;
    MIPEditionCollection internal collection;
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        implementation = new MIPEditionCollection();
        collection = MIPEditionCollection(Clones.clone(address(implementation)));
        collection.initialize(1, creator, "My Editions", "MED", "ipfs://base/");
    }

    function test_initialize_setsState() public view {
        assertEq(collection.collectionId(), 1);
        assertEq(collection.registry(), address(this));
        assertEq(collection.owner(), creator);
        assertEq(collection.collectionCreator(), creator);
        assertEq(collection.name(), "My Editions");
        assertEq(collection.symbol(), "MED");
        assertEq(collection.collectionBaseUri(), "ipfs://base/");
        assertEq(collection.version(), "1.0.0");
        assertEq(collection.totalEditions(), 0);
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
        MIPEditionCollection blank = MIPEditionCollection(Clones.clone(address(implementation)));
        vm.expectRevert(MIPEditionCollection.MIPInvalidName.selector);
        blank.initialize(1, creator, "", "MED", "");
        vm.expectRevert(MIPEditionCollection.MIPInvalidSymbol.selector);
        blank.initialize(1, creator, "My Editions", "", "");
    }

    function test_mintEdition_sequentialWithSupplyAndUri() public {
        vm.startPrank(creator);
        uint256 first = collection.mintEdition(alice, 100, "ipfs://ed/1");
        uint256 second = collection.mintEdition(bob, 1, "ipfs://ed/2");
        vm.stopPrank();
        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(collection.balanceOf(alice, 1), 100);
        assertEq(collection.balanceOf(bob, 2), 1);
        assertEq(collection.uri(1), "ipfs://ed/1");
        assertEq(collection.totalEditions(), 2);
        assertTrue(collection.tokenExists(1));
        assertFalse(collection.tokenExists(3));
        assertEq(collection.getTokenCreator(1), creator);
    }

    function test_mintEdition_recordsRegistrationRecord() public {
        vm.warp(1_720_000_000);
        vm.prank(creator);
        uint256 id = collection.mintEdition(alice, 100, "ipfs://ed/1");
        assertEq(collection.getTokenRegisteredAt(id), 1_720_000_000);
        (string memory metadataUri, address originalCreator, uint64 registeredAt) = collection.getTokenData(id);
        assertEq(metadataUri, "ipfs://ed/1");
        assertEq(originalCreator, creator);
        assertEq(registeredAt, 1_720_000_000);
    }

    function test_recordViews_revertForUnknownEdition() public {
        vm.expectRevert(abi.encodeWithSelector(MIPEditionCollection.MIPUnknownEdition.selector, 1));
        collection.getTokenCreator(1);
        vm.expectRevert(abi.encodeWithSelector(MIPEditionCollection.MIPUnknownEdition.selector, 1));
        collection.getTokenRegisteredAt(1);
        vm.expectRevert(abi.encodeWithSelector(MIPEditionCollection.MIPUnknownEdition.selector, 1));
        collection.getTokenData(1);
    }

    function test_uri_fallsBackToBaseUri() public {
        assertEq(collection.uri(1), "ipfs://base/");
        vm.prank(creator);
        uint256 id = collection.mintEdition(alice, 1, "ipfs://ed/1");
        assertEq(collection.uri(id), "ipfs://ed/1");
        assertEq(collection.uri(id + 1), "ipfs://base/");
    }

    function test_mintEdition_emitsAndGates() public {
        vm.expectEmit(true, true, false, true);
        emit MIPEditionCollection.EditionMinted(1, alice, 100, "ipfs://ed/1");
        vm.prank(creator);
        collection.mintEdition(alice, 100, "ipfs://ed/1");
        vm.prank(alice);
        vm.expectRevert();
        collection.mintEdition(alice, 1, "ipfs://ed/x");
    }

    function test_mintEdition_zeroValueReverts() public {
        vm.prank(creator);
        vm.expectRevert(MIPEditionCollection.MIPZeroValue.selector);
        collection.mintEdition(alice, 0, "ipfs://ed/1");
    }

    function test_mintEdition_emptyUriReverts() public {
        vm.prank(creator);
        vm.expectRevert(MIPEditionCollection.MIPInvalidTokenUri.selector);
        collection.mintEdition(alice, 1, "");
    }

    function test_batchMintEdition_singleRecipient() public {
        uint256[] memory values = new uint256[](2);
        values[0] = 10;
        values[1] = 20;
        string[] memory uris = new string[](2);
        uris[0] = "ipfs://1";
        uris[1] = "ipfs://2";
        vm.prank(creator);
        uint256[] memory ids = collection.batchMintEdition(alice, values, uris);
        assertEq(ids.length, 2);
        assertEq(collection.balanceOf(alice, ids[0]), 10);
        assertEq(collection.balanceOf(alice, ids[1]), 20);
        assertEq(collection.uri(ids[0]), "ipfs://1");
        assertEq(collection.getTokenCreator(ids[1]), creator);
    }

    function test_batchMintEdition_lengthMismatchReverts() public {
        uint256[] memory values = new uint256[](1);
        string[] memory uris = new string[](2);
        vm.prank(creator);
        vm.expectRevert(MIPEditionCollection.MIPLengthMismatch.selector);
        collection.batchMintEdition(alice, values, uris);
    }

    function test_addSupply_growsExistingEdition() public {
        vm.prank(creator);
        uint256 id = collection.mintEdition(alice, 100, "ipfs://ed/1");
        vm.expectEmit(true, true, false, true);
        emit MIPEditionCollection.SupplyAdded(id, bob, 50);
        vm.prank(creator);
        collection.addSupply(bob, id, 50);
        assertEq(collection.balanceOf(bob, id), 50);
        assertEq(collection.totalEditions(), 1);
    }

    function test_addSupply_keepsRegistrationRecord() public {
        vm.warp(1_720_000_000);
        vm.prank(creator);
        uint256 id = collection.mintEdition(alice, 1, "ipfs://ed/1");
        vm.warp(1_720_009_999);
        vm.prank(creator);
        collection.addSupply(bob, id, 5);
        assertEq(collection.getTokenRegisteredAt(id), 1_720_000_000);
        assertEq(collection.getTokenCreator(id), creator);
    }

    function test_addSupply_unknownEditionReverts() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(MIPEditionCollection.MIPUnknownEdition.selector, 9));
        collection.addSupply(alice, 9, 1);
    }

    function test_addSupply_zeroValueReverts() public {
        vm.prank(creator);
        uint256 id = collection.mintEdition(alice, 1, "ipfs://ed/1");
        vm.prank(creator);
        vm.expectRevert(MIPEditionCollection.MIPZeroValue.selector);
        collection.addSupply(alice, id, 0);
    }

    function test_addSupply_onlyOwner() public {
        vm.prank(creator);
        uint256 id = collection.mintEdition(alice, 1, "ipfs://ed/1");
        vm.prank(alice);
        vm.expectRevert();
        collection.addSupply(alice, id, 1);
    }

    function test_royalty_startsAtZeroAndIsOwnerManaged() public {
        vm.prank(creator);
        uint256 id = collection.mintEdition(alice, 1, "ipfs://ed/1");
        (address receiver, uint256 amount) = collection.royaltyInfo(id, 10_000);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
        vm.prank(creator);
        collection.setDefaultRoyalty(creator, 500);
        (receiver, amount) = collection.royaltyInfo(id, 10_000);
        assertEq(receiver, creator);
        assertEq(amount, 500);
        // per-edition override wins over the default, and reset restores it
        vm.prank(creator);
        collection.setTokenRoyalty(id, bob, 100);
        (receiver, amount) = collection.royaltyInfo(id, 10_000);
        assertEq(receiver, bob);
        assertEq(amount, 100);
        vm.prank(creator);
        collection.resetTokenRoyalty(id);
        (receiver, amount) = collection.royaltyInfo(id, 10_000);
        assertEq(receiver, creator);
        assertEq(amount, 500);
        vm.prank(creator);
        collection.deleteDefaultRoyalty();
        (receiver, amount) = collection.royaltyInfo(id, 10_000);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    function test_royalty_adminIsOwnerGated() public {
        vm.prank(alice);
        vm.expectRevert();
        collection.setDefaultRoyalty(alice, 100);
        vm.prank(alice);
        vm.expectRevert();
        collection.setTokenRoyalty(1, alice, 100);
    }

    function testFuzz_mintEdition(address to, uint96 value, string calldata metadataUri) public {
        vm.assume(to != address(0) && to.code.length == 0);
        value = uint96(bound(value, 1, type(uint96).max));
        vm.assume(bytes(metadataUri).length > 0 && bytes(metadataUri).length <= 2048);
        vm.prank(creator);
        uint256 id = collection.mintEdition(to, value, metadataUri);
        assertEq(collection.balanceOf(to, id), value);
        assertEq(collection.uri(id), metadataUri);
    }
}

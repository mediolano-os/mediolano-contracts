// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MIPCollection} from "../src/MIPCollection.sol";

contract MIPCollectionArchiveTest is Test {
    MIPCollection internal collection;
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        collection = MIPCollection(Clones.clone(address(new MIPCollection())));
        collection.initialize(1, creator, "My IP", "MIP", "", 500);
    }

    function test_batchMint_mintsAllAndReturnsIds() public {
        address[] memory to = new address[](2);
        to[0] = alice;
        to[1] = bob;
        string[] memory uris = new string[](2);
        uris[0] = "ipfs://1";
        uris[1] = "ipfs://2";
        vm.prank(creator);
        uint256[] memory ids = collection.batchMint(to, uris);
        assertEq(ids.length, 2);
        assertEq(collection.ownerOf(ids[0]), alice);
        assertEq(collection.ownerOf(ids[1]), bob);
        assertEq(collection.tokenURI(ids[1]), "ipfs://2");
    }

    function test_batchMint_revertsOnLengthMismatch() public {
        address[] memory to = new address[](2);
        string[] memory uris = new string[](1);
        vm.prank(creator);
        vm.expectRevert(MIPCollection.MIPLengthMismatch.selector);
        collection.batchMint(to, uris);
    }

    function test_archive_blocksTransfer() public {
        vm.prank(creator);
        uint256 id = collection.mint(alice, "ipfs://1");
        vm.prank(creator);
        collection.archive(id);
        assertTrue(collection.isArchived(id));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MIPCollection.MIPTokenArchived.selector, id));
        collection.transferFrom(alice, bob, id);
    }

    function test_archive_emitsAndRejectsDoubleArchive() public {
        vm.prank(creator);
        uint256 id = collection.mint(alice, "ipfs://1");
        vm.expectEmit(true, false, false, false);
        emit MIPCollection.TokenArchived(id);
        vm.prank(creator);
        collection.archive(id);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(MIPCollection.MIPAlreadyArchived.selector, id));
        collection.archive(id);
    }

    function test_archive_onlyOwner() public {
        vm.prank(creator);
        uint256 id = collection.mint(alice, "ipfs://1");
        vm.prank(alice);
        vm.expectRevert();
        collection.archive(id);
    }

    function test_royalty_setAtInitAndAdjustable() public {
        vm.prank(creator);
        collection.mint(alice, "ipfs://1");
        (address receiver, uint256 amount) = collection.royaltyInfo(1, 10_000);
        assertEq(receiver, creator);
        assertEq(amount, 500);
        vm.prank(creator);
        collection.setDefaultRoyalty(bob, 100);
        (receiver, amount) = collection.royaltyInfo(1, 10_000);
        assertEq(receiver, bob);
        assertEq(amount, 100);
    }

    function testFuzz_mint_anyRecipientAndUri(address to, string calldata uri) public {
        vm.assume(to != address(0) && to.code.length == 0);
        vm.prank(creator);
        uint256 id = collection.mint(to, uri);
        assertEq(collection.ownerOf(id), to);
        assertEq(collection.tokenURI(id), uri);
    }
}

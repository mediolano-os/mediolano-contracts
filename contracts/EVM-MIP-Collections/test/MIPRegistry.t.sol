// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MIPCollection} from "../src/MIPCollection.sol";
import {MIPRegistry} from "../src/MIPRegistry.sol";

contract MIPRegistryTest is Test {
    MIPRegistry internal registryContract;
    address internal creator = makeAddr("creator");
    address internal other = makeAddr("other");

    function setUp() public {
        registryContract = new MIPRegistry(address(new MIPCollection()));
    }

    function test_createCollection_isPermissionlessAndSequential() public {
        vm.prank(creator);
        (uint256 firstId, address firstAddr) = registryContract.createCollection("A", "AAA", "ipfs://a/");
        vm.prank(other);
        (uint256 secondId, address secondAddr) = registryContract.createCollection("B", "BBB", "");
        assertEq(firstId, 1);
        assertEq(secondId, 2);
        assertTrue(firstAddr != secondAddr);
        assertEq(registryContract.collectionCount(), 2);
    }

    function test_createCollection_initializesCloneForCaller() public {
        vm.prank(creator);
        (uint256 id, address addr) = registryContract.createCollection("A", "AAA", "ipfs://a/");
        MIPCollection c = MIPCollection(addr);
        assertEq(c.owner(), creator);
        assertEq(c.collectionId(), id);
        assertEq(c.registry(), address(registryContract));
        assertEq(c.name(), "A");
        vm.prank(creator);
        c.mint(creator, "ipfs://a/1", 250);
        (address receiver, uint256 amount) = c.royaltyInfo(1, 10_000);
        assertEq(receiver, creator);
        assertEq(amount, 250);
    }

    function test_createCollection_recordsAndValidates() public {
        vm.prank(creator);
        (uint256 id, address addr) = registryContract.createCollection("A", "AAA", "");
        (address storedAddr, address storedCreator) = registryContract.getCollection(id);
        assertEq(storedAddr, addr);
        assertEq(storedCreator, creator);
        assertTrue(registryContract.isValidCollection(id));
        assertFalse(registryContract.isValidCollection(99));
    }

    function test_createCollection_rejectsInvalidInputs() public {
        vm.expectRevert(MIPCollection.MIPInvalidName.selector);
        registryContract.createCollection("", "AAA", "");
        vm.expectRevert(MIPCollection.MIPInvalidSymbol.selector);
        registryContract.createCollection("A", "", "");
    }

    function test_createCollection_emitsCollectionCreated() public {
        vm.expectEmit(true, false, true, true);
        emit MIPRegistry.CollectionCreated(1, address(0), creator, "A", "AAA", "ipfs://a/");
        vm.prank(creator);
        registryContract.createCollection("A", "AAA", "ipfs://a/");
    }

    function test_registry_hasNoOwnerSurface() public view {
        assertEq(registryContract.version(), "1.0.0");
        assertTrue(registryContract.collectionImplementation() != address(0));
    }
}

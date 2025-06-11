/**
 * SPDX-License-Identifier: GPL-3.0
 * Foundry tests for the MiniMart marketplace.
 *
 * NOTE
 * ──────────────────────────────────────────────────────────────────────────────
 * • These tests exercise the full public API of the MiniMart contract and try
 *   to cover as many invariants / edge-cases as possible using a combination of
 *   example-based, fuzz-based and stateful testing.
 * • Run with `forge test -vv`
 */
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MiniMart.sol";
import "../src/TestNFT.sol";

contract MiniMartTest is Test {
    MiniMart     internal miniMart;
    TestNFT      internal nft;
    TestNFT      internal otherNft;

    // ──────────────────────────────────────────────────────────────────────────
    // Test actors ‑ we give them ETH in `setUp`
    // ──────────────────────────────────────────────────────────────────────────
    address internal owner   = address(0xA11CE);
    address internal seller  = address(0xB0B);
    uint256 internal sellerPk = uint256(0xB0B);           // private key for vm.sign
    address internal buyer   = address(0xCAFE);
    uint256 internal buyerPk  = uint256(0xCAFE);

    // helper constant
    uint256 internal constant TOKEN_ID = 0;

    // ──────────────────────────────────────────────────────────────────────────
    // setUp
    // ──────────────────────────────────────────────────────────────────────────
    function setUp() public {
        // label addresses for nicer traces
        vm.label(owner,  "Owner");
        vm.label(seller, "Seller");
        vm.label(buyer,  "Buyer");

        // provide funds
        vm.deal(owner,  100 ether);
        vm.deal(seller, 100 ether);
        vm.deal(buyer,  100 ether);

        // deploy MiniMart
        vm.prank(owner);
        miniMart = new MiniMart(owner, "MiniMart", "1");

        // deploy NFTs
        nft      = new TestNFT("ipfs://base", seller);
        otherNft = new TestNFT("ipfs://other", seller);

        // mint one token for seller (tokenId = 0)
        vm.prank(seller);
        nft.mint(seller);
        vm.prank(seller);
        otherNft.mint(seller);

        // whitelist `nft`, leave `otherNft` un-whitelisted
        vm.prank(owner);
        miniMart.setWhitelistStatus(address(nft), true);

        // seller approves marketplace for tokenId 0
        vm.prank(seller);
        nft.approve(address(miniMart), TOKEN_ID);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────────
    /**
     * Creates an order struct + signature convenient for the tests.
     */
    function _createOrder(
        uint256 price,
        uint64  expiration,
        uint64  nonce
    )
        internal
        returns (MiniMart.Order memory order, bytes memory signature, bytes32 digest)
    {
        order = MiniMart.Order({
            price:      price,
            tokenId:    TOKEN_ID,
            nftContract:address(nft),
            seller:     seller,
            expiration: expiration,
            nonce:      nonce
        });

        digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ listing
    // ──────────────────────────────────────────────────────────────────────────
    function testAddOrderSuccess() public {
        (MiniMart.Order memory order, bytes memory sig, bytes32 digest) =
            _createOrder(1 ether, 0, 0);

        // anyone can submit the listing tx, does not have to be the seller
        vm.prank(buyer);
        bytes32 returnedHash = miniMart.addOrder(order, sig);

        assertEq(returnedHash, digest, "Digest mismatch");
        MiniMart.Order memory stored = miniMart.getOrder(digest);
        assertEq(stored.price, order.price, "Price mismatch");
        assertEq(miniMart.nonces(seller), 1, "Nonce should increment");
    }

    function testAddOrderFailsIfNotWhitelisted() public {
        // build order for `otherNft` which is NOT whitelisted
        MiniMart.Order memory badOrder = MiniMart.Order({
            price:      1 ether,
            tokenId:    TOKEN_ID,
            nftContract:address(otherNft),
            seller:     seller,
            expiration: 0,
            nonce:      0
        });

        bytes32 digest = miniMart.hashOrder(badOrder);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.NotWhitelisted.selector);
        vm.prank(buyer);
        miniMart.addOrder(badOrder, sig);
    }

    function testAddOrderFailsWithWrongNonce() public {
        (MiniMart.Order memory order, bytes memory sig, ) =
            _createOrder(1 ether, 0, 5); // wrong nonce == 5

        vm.expectRevert(MiniMart.NonceIncorrect.selector);
        miniMart.addOrder(order, sig);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ fulfillment
    // ──────────────────────────────────────────────────────────────────────────
    function testFulfillOrderSuccess() public {
        (MiniMart.Order memory order, bytes memory sig, bytes32 digest) =
            _createOrder(2 ether, 0, 0);

        miniMart.addOrder(order, sig);

        // before fulfillment seller owns token
        assertEq(nft.ownerOf(TOKEN_ID), seller);

        // track balances
        uint256 sellerBefore = seller.balance;
        uint256 ownerBefore  = owner.balance;

        uint256 fee = (order.price * miniMart.FEE_BPS()) / 10_000;

        // buyer buys
        vm.prank(buyer);
        miniMart.fulfillOrder{value: order.price}(digest);

        // token ownership transferred
        assertEq(nft.ownerOf(TOKEN_ID), buyer, "token should transfer");

        // order should be removed
        MiniMart.Order memory empty = miniMart.getOrder(digest);
        assertEq(empty.seller, address(0), "order not deleted");

        // balances updated
        assertEq(seller.balance, sellerBefore + order.price - fee, "seller paid");
        assertEq(owner.balance,  ownerBefore          + fee,       "fee collected");
    }

    function testFulfillOrderFailsWrongPrice() public {
        (MiniMart.Order memory order, bytes memory sig, bytes32 digest) =
            _createOrder(1 ether, 0, 0);

        miniMart.addOrder(order, sig);

        vm.expectRevert(MiniMart.OrderPriceWrong.selector);
        vm.prank(buyer);
        miniMart.fulfillOrder{value: order.price - 1 wei}(digest);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ removing orders
    // ──────────────────────────────────────────────────────────────────────────
    function testRemoveOrderBySeller() public {
        (MiniMart.Order memory order, bytes memory sig, bytes32 digest) =
            _createOrder(1 ether, 0, 0);

        miniMart.addOrder(order, sig);

        vm.prank(seller);
        miniMart.removeOrder(digest);

        MiniMart.Order memory removed = miniMart.getOrder(digest);
        assertEq(removed.seller, address(0), "order not removed");
    }

    function testRemoveOrderFailsIfNotSeller() public {
        (MiniMart.Order memory order, bytes memory sig, bytes32 digest) =
            _createOrder(1 ether, 0, 0);

        miniMart.addOrder(order, sig);

        vm.expectRevert(MiniMart.NotListingCreator.selector);
        vm.prank(buyer);
        miniMart.removeOrder(digest);
    }

    function testBatchRemoveOrders() public {
        bytes32[] memory hashes = new bytes32[](3);

        for(uint8 i; i < 3; ++i){
            (MiniMart.Order memory order, bytes memory sig, bytes32 digest) =
                _createOrder(0.5 ether + i, 0, i); // price different, nonce incrementing
            hashes[i] = digest;
            miniMart.addOrder(order, sig);
        }

        vm.prank(seller);
        miniMart.batchRemoveOrder(hashes);

        for(uint8 i; i < 3; ++i){
            MiniMart.Order memory check = miniMart.getOrder(hashes[i]);
            assertEq(check.seller, address(0), "order not removed");
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ admin / whitelist
    // ──────────────────────────────────────────────────────────────────────────
    function testSetWhitelistStatus() public {
        // contract is currently NOT whitelisted
        assertTrue(!miniMart.whitelist(address(otherNft)));

        vm.prank(owner);
        miniMart.setWhitelistStatus(address(otherNft), true);
        assertTrue(miniMart.whitelist(address(otherNft)));

        vm.prank(owner);
        miniMart.setWhitelistStatus(address(otherNft), false);
        assertTrue(!miniMart.whitelist(address(otherNft)));
    }

    function testSetWhitelistFailsIfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(seller);
        miniMart.setWhitelistStatus(address(otherNft), true);
    }

    function testWithdrawFees() public {
        // create an order & fulfill to generate fees
        (MiniMart.Order memory order, bytes memory sig, bytes32 digest) =
            _createOrder(3 ether, 0, 0);
        miniMart.addOrder(order, sig);
        vm.prank(buyer);
        miniMart.fulfillOrder{value: order.price}(digest);

        uint256 ownerBefore = owner.balance;
        uint256 contractBal = address(miniMart).balance;

        assertGt(contractBal, 0, "no fees to withdraw");

        vm.prank(owner);
        miniMart.withdrawFees();

        assertEq(address(miniMart).balance, 0, "fees not withdrawn");
        assertEq(owner.balance, ownerBefore + contractBal, "owner not paid");
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Invariant ‑ nonces always strictly increase per seller
    // ──────────────────────────────────────────────────────────────────────────
    // Fuzz test: generate multiple listings in random order and ensure nonce
    // monotonicity.
    function testFuzz_NonceMonotonicity(uint96 price, uint64 runs) public {
        price = uint96(bound(uint256(price), 10_000_000_000_000, 1 ether)); // bound ≥ min price
        runs  = uint64(bound(uint256(runs), 1, 20));

        for(uint64 i; i < runs; ++i){
            (MiniMart.Order memory order, bytes memory sig, ) =
                _createOrder(price, 0, i);
            miniMart.addOrder(order, sig);
        }
        assertEq(miniMart.nonces(seller), runs, "nonce did not advance correctly");
    }
}

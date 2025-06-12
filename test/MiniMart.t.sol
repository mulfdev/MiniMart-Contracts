/**
 * SPDX-License-Identifier: GPL-3.0
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
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/* ─────────────────────────────────────────────────────────────────────────────
 * Helper mocks
 * ────────────────────────────────────────────────────────────────────────────*/
/// @dev Contract that does NOT implement ERC165 – used to trigger NonERC721Interface.
contract NonERC165 { }

/// @dev Owner that reverts on receiving ETH – used to trigger FeeWithdrawlFailed.
contract RevertingOwner {
    function callWithdraw(MiniMart mart) external {
        mart.withdrawFees();
    }

    receive() external payable {
        revert();
    }
}

// keep the declaration so the file compiles even though the selector
// is referenced explicitly below.
error OwnableUnauthorizedAccount(address);

contract MiniMartTest is Test {
    MiniMart internal miniMart;
    TestNFT internal nft;
    TestNFT internal otherNft;

    // ──────────────────────────────────────────────────────────────────────────
    // Test actors (private keys are deterministic so we can sign orders)
    // ──────────────────────────────────────────────────────────────────────────
    uint256 internal constant sellerPk = uint256(0xB0B);
    uint256 internal constant buyerPk = uint256(0xCAFE);

    address internal owner;
    address internal seller;
    address internal buyer;

    // helper constant
    uint256 internal constant TOKEN_ID = 0;

    // ──────────────────────────────────────────────────────────────────────────
    // setUp
    // ──────────────────────────────────────────────────────────────────────────
    function setUp() public {
        // derive addresses from private keys so signatures recover correctly
        owner = vm.addr(uint256(1));
        seller = vm.addr(sellerPk);
        buyer = vm.addr(buyerPk);

        // label addresses for nicer traces
        vm.label(owner, "Owner");
        vm.label(seller, "Seller");
        vm.label(buyer, "Buyer");

        // provide funds
        vm.deal(owner, 100 ether);
        vm.deal(seller, 100 ether);
        vm.deal(buyer, 100 ether);

        // deploy MiniMart
        vm.prank(owner);
        miniMart = new MiniMart(owner, "MiniMart", "1");

        // deploy NFTs
        nft = new TestNFT("ipfs://base", seller);
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
    // Unit tests ‑ listing (success paths)
    // ──────────────────────────────────────────────────────────────────────────
    function testAddOrderSuccess() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // anyone can submit the listing tx, does not have to be the seller
        vm.prank(buyer);
        bytes32 returnedHash = miniMart.addOrder(order, sig);

        assertEq(returnedHash, digest, "Digest mismatch");
        MiniMart.Order memory stored = miniMart.getOrder(digest);
        assertEq(stored.price, order.price, "Price mismatch");
        assertEq(miniMart.nonces(seller), 1, "Nonce should increment");
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ listing (negative paths)
    // ──────────────────────────────────────────────────────────────────────────
    function testAddOrderFailsIfNotWhitelisted() public {
        // build order for `otherNft` which is NOT whitelisted
        MiniMart.Order memory badOrder = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(otherNft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(badOrder);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.NotWhitelisted.selector);
        vm.prank(buyer);
        miniMart.addOrder(badOrder, sig);
    }

    function testAddOrderFailsWithWrongNonce() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 5 // wrong nonce
         });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.NonceIncorrect.selector);
        miniMart.addOrder(order, sig);
    }

    function testAddOrderFails_SignerMustBeSeller() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        // seller signs correctly
        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);

        // tamper order so seller field no longer matches signature
        order.seller = buyer;

        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.SignerMustBeSeller.selector);
        miniMart.addOrder(order, sig);
    }

    function testAddOrderFails_OrderExpired() public {
        uint64 expiry = uint64(block.timestamp + 1);

        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: expiry,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Advance time so that the order is already expired at submission
        vm.warp(block.timestamp + 2);

        vm.expectRevert(MiniMart.OrderExpired.selector);
        miniMart.addOrder(order, sig);
    }

    function testAddOrderFails_PriceTooLow() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 wei,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.OrderPriceTooLow.selector);
        miniMart.addOrder(order, sig);
    }

    function testAddOrderFails_NonERC721Interface() public {
        NonERC165 bogus = new NonERC165();

        // whitelist the bogus contract so that the ERC721 interface check is reached
        vm.prank(owner);
        miniMart.setWhitelistStatus(address(bogus), true);

        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(bogus),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.NonERC721Interface.selector);
        miniMart.addOrder(order, sig);
    }

    function testAddOrderFails_MarketplaceNotApproved() public {
        // revoke approval
        vm.prank(seller);
        nft.approve(address(0), TOKEN_ID);

        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.MarketplaceNotApproved.selector);
        miniMart.addOrder(order, sig);
    }

    function testAddOrderFails_AlreadyListed() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        vm.expectRevert(MiniMart.AlreadyListed.selector);
        miniMart.addOrder(order, sig);

        MiniMart.Order memory stored = miniMart.getOrder(digest);
        assertEq(stored.seller, seller);
    }

    function testAddOrderFails_NotTokenOwner() public {
        // transfer token away from seller (keep approval)
        vm.prank(seller);
        nft.transferFrom(seller, buyer, TOKEN_ID);
        vm.prank(buyer);
        nft.approve(address(miniMart), TOKEN_ID);

        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MiniMart.NotTokenOwner.selector);
        miniMart.addOrder(order, sig);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ fulfillment (success path)
    // ──────────────────────────────────────────────────────────────────────────
    function testFulfillOrderSuccess() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 2 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        // before fulfillment seller owns token
        assertEq(nft.ownerOf(TOKEN_ID), seller);

        // track balances
        uint256 sellerBefore = seller.balance;
        uint256 ownerBefore = owner.balance;
        uint256 contractBefore = address(miniMart).balance;

        uint256 fee = (order.price * miniMart.FEE_BPS()) / 10_000;

        // buyer buys
        vm.prank(buyer);
        miniMart.fulfillOrder{ value: order.price }(digest);

        // token ownership transferred
        assertEq(nft.ownerOf(TOKEN_ID), buyer, "token should transfer");

        // order should be removed
        MiniMart.Order memory empty = miniMart.getOrder(digest);
        assertEq(empty.seller, address(0), "order not deleted");

        // balances updated
        assertEq(seller.balance, sellerBefore + order.price - fee, "seller paid");
        // fee stays inside the contract until `withdrawFees`
        assertEq(owner.balance, ownerBefore, "owner should NOT receive fee yet");
        assertEq(address(miniMart).balance, contractBefore + fee, "contract should hold the fee");
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ fulfillment (negative paths that now REFUND instead of revert)
    // ──────────────────────────────────────────────────────────────────────────
    function testFulfillRefunds_OrderExpired() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: uint64(block.timestamp + 1),
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        // order will be expired
        vm.warp(block.timestamp + 3);

        uint256 buyerBefore = buyer.balance;
        uint256 contractBefore = address(miniMart).balance;

        vm.expectEmit(true, true, true, true);
        emit MiniMart.OrderRemoved(digest);

        vm.prank(buyer);
        miniMart.fulfillOrder{ value: order.price }(digest);

        // order removed
        assertEq(miniMart.getOrder(digest).seller, address(0), "order not removed");

        // buyer refunded (tolerate gas)
        assertApproxEqAbs(buyer.balance, buyerBefore, 1e14);

        // contract balance unchanged
        assertEq(address(miniMart).balance, contractBefore, "contract should not keep funds");
    }

    function testFulfillRefunds_NotTokenOwner() public {
        // LIST
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: miniMart.nonces(seller)
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        // seller no longer owns token
        vm.prank(seller);
        nft.transferFrom(seller, owner, TOKEN_ID);

        uint256 buyerBefore = buyer.balance;
        uint256 contractBefore = address(miniMart).balance;

        vm.expectEmit(true, true, true, true);
        emit MiniMart.OrderRemoved(digest);

        vm.prank(buyer);
        miniMart.fulfillOrder{ value: 1 ether }(digest);

        assertEq(miniMart.getOrder(digest).seller, address(0), "order not removed");
        assertApproxEqAbs(buyer.balance, buyerBefore, 1e14);
        assertEq(address(miniMart).balance, contractBefore);
    }

    function testFulfillRefunds_MarketplaceNotApproved() public {
        // LIST
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: miniMart.nonces(seller)
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        // revoke approval
        vm.prank(seller);
        nft.approve(address(0), TOKEN_ID);

        uint256 buyerBefore = buyer.balance;
        uint256 contractBefore = address(miniMart).balance;

        vm.expectEmit(true, true, true, true);
        emit MiniMart.OrderRemoved(digest);

        vm.prank(buyer);
        miniMart.fulfillOrder{ value: 1 ether }(digest);

        assertEq(miniMart.getOrder(digest).seller, address(0), "order not removed");
        assertApproxEqAbs(buyer.balance, buyerBefore, 1e14);
        assertEq(address(miniMart).balance, contractBefore);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ fulfillment (negative paths that still revert)
    // ──────────────────────────────────────────────────────────────────────────
    function testFulfillOrderFailsWrongPrice() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        vm.expectRevert(MiniMart.OrderPriceWrong.selector);
        vm.prank(buyer);
        miniMart.fulfillOrder{ value: order.price - 1 wei }(digest);
    }

    function testFulfillFails_OrderNotFound() public {
        vm.expectRevert(MiniMart.OrderNotFound.selector);
        miniMart.fulfillOrder{ value: 1 ether }(bytes32(uint256(123)));
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Unit tests ‑ removing orders
    // ──────────────────────────────────────────────────────────────────────────
    function testRemoveOrderBySeller() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        vm.prank(seller);
        miniMart.removeOrder(digest);

        MiniMart.Order memory removed = miniMart.getOrder(digest);
        assertEq(removed.seller, address(0), "order not removed");
    }

    function testRemoveOrderFailsIfNotSeller() public {
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);

        vm.expectRevert(MiniMart.NotListingCreator.selector);
        vm.prank(buyer);
        miniMart.removeOrder(digest);
    }

    function testRemoveOrderFails_OrderNotFound() public {
        vm.expectRevert(MiniMart.OrderNotFound.selector);
        miniMart.removeOrder(bytes32(uint256(42)));
    }

    function testBatchRemoveOrders() public {
        bytes32[] memory hashes = new bytes32[](3);

        for (uint8 i; i < 3; ++i) {
            MiniMart.Order memory order = MiniMart.Order({
                price: 0.5 ether + i,
                tokenId: TOKEN_ID,
                nftContract: address(nft),
                seller: seller,
                taker: address(0),
                expiration: 0,
                nonce: i
            });

            bytes32 digest = miniMart.hashOrder(order);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
            bytes memory sig = abi.encodePacked(r, s, v);

            hashes[i] = digest;
            miniMart.addOrder(order, sig);
        }

        vm.prank(seller);
        miniMart.batchRemoveOrder(hashes);

        for (uint8 i; i < 3; ++i) {
            MiniMart.Order memory check = miniMart.getOrder(hashes[i]);
            assertEq(check.seller, address(0), "order not removed");
        }
    }

    function testBatchRemoveFails_InvalidBatchSize() public {
        bytes32[] memory empty;
        vm.expectRevert(MiniMart.InvalidBatchSize.selector);
        miniMart.batchRemoveOrder(empty);
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

    function testWhitelistStatusAlreadySet() public {
        // current status is already `true`
        vm.prank(owner);
        vm.expectRevert(MiniMart.StatusAlreadySet.selector);
        miniMart.setWhitelistStatus(address(nft), true);
    }

    function testSetWhitelistFailsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, seller));
        vm.prank(seller);
        miniMart.setWhitelistStatus(address(otherNft), true);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // withdrawFees
    // ──────────────────────────────────────────────────────────────────────────
    function testWithdrawFees() public {
        // create an order & fulfill to generate fees
        MiniMart.Order memory order = MiniMart.Order({
            price: 3 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });

        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        miniMart.addOrder(order, sig);
        vm.prank(buyer);
        miniMart.fulfillOrder{ value: order.price }(digest);

        uint256 ownerBefore = owner.balance;
        uint256 contractBal = address(miniMart).balance;

        assertGt(contractBal, 0, "no fees to withdraw");

        vm.prank(owner);
        miniMart.withdrawFees();

        assertEq(address(miniMart).balance, 0, "fees not withdrawn");
        assertEq(owner.balance, ownerBefore + contractBal, "owner not paid");
    }

    function testWithdrawFeesFails_FeeWithdraw() public {
        // deploy new mart with an owner that rejects ETH
        RevertingOwner badOwner = new RevertingOwner();
        MiniMart badMart = new MiniMart(address(badOwner), "Mini", "1");

        // deploy nft & whitelist it
        TestNFT localNft = new TestNFT("uri", seller);
        vm.prank(address(badOwner));
        badMart.setWhitelistStatus(address(localNft), true);

        // mint & approve
        vm.prank(seller);
        localNft.mint(seller);
        vm.prank(seller);
        localNft.approve(address(badMart), 0);

        // list order
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: 0,
            nftContract: address(localNft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });
        bytes32 digest = badMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        vm.prank(buyer);
        badMart.addOrder(order, abi.encodePacked(r, s, v));

        // fulfill to accrue fees
        vm.prank(buyer);
        badMart.fulfillOrder{ value: 1 ether }(digest);

        vm.expectRevert(MiniMart.FeeWithdrawlFailed.selector);
        badOwner.callWithdraw(badMart);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Pause / Unpause
    // ──────────────────────────────────────────────────────────────────────────
    function testPauseAndUnpauseByOwner() public {
        // pause the contract
        vm.prank(owner);
        miniMart.pauseContract();

        // verify that state-changing functions guarded by whenNotPaused revert
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });
        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(buyer);
        miniMart.addOrder(order, sig);

        // unpause
        vm.prank(owner);
        miniMart.unpause();

        // now addOrder succeeds
        vm.prank(buyer);
        miniMart.addOrder(order, sig);

        MiniMart.Order memory stored = miniMart.getOrder(digest);
        assertEq(stored.seller, seller, "order not stored after unpause");
    }

    function testPauseAccessControl() public {
        // non-owner should not be able to pause
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, seller));
        vm.prank(seller);
        miniMart.pauseContract();

        // owner pauses
        vm.prank(owner);
        miniMart.pauseContract();

        // non-owner cannot unpause
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, seller));
        vm.prank(seller);
        miniMart.unpause();
    }

    function testFulfillOrderFailsWhenPaused() public {
        // create & list order while unpaused
        MiniMart.Order memory order = MiniMart.Order({
            price: 1 ether,
            tokenId: TOKEN_ID,
            nftContract: address(nft),
            seller: seller,
            taker: address(0),
            expiration: 0,
            nonce: 0
        });
        bytes32 digest = miniMart.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        miniMart.addOrder(order, sig);

        // pause
        vm.prank(owner);
        miniMart.pauseContract();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(buyer);
        miniMart.fulfillOrder{ value: order.price }(digest);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Invariant ‑ nonces always strictly increase per seller
    // ──────────────────────────────────────────────────────────────────────────
    function testFuzz_NonceMonotonicity(uint96 price, uint64 runs) public {
        price = uint96(bound(uint256(price), 10_000_000_000_000, 1 ether)); // ≥ min price
        runs = uint64(bound(uint256(runs), 1, 20));

        for (uint64 i; i < runs; ++i) {
            MiniMart.Order memory order = MiniMart.Order({
                price: price,
                tokenId: TOKEN_ID,
                nftContract: address(nft),
                seller: seller,
                taker: address(0),
                expiration: 0,
                nonce: i
            });

            bytes32 digest = miniMart.hashOrder(order);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
            bytes memory sig = abi.encodePacked(r, s, v);

            miniMart.addOrder(order, sig);
        }

        assertEq(miniMart.nonces(seller), runs, "nonce did not advance correctly");
    }
}

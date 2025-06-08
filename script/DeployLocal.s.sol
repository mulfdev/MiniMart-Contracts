// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {console} from "forge-std/console.sol";
import {MiniMart} from "../src/MiniMart.sol";
import {TestNFT} from "../src/TestNFT.sol";

contract DeployLocal is Script, EIP712 {
    constructor() EIP712("MiniMart", "1") {}

    MiniMart public marketplace;

    function setUp() public {}

    function run() public {
        vm.createSelectFork("local");

        // DONT PANICK, this is an anvil provided private key
        uint256 privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        vm.startBroadcast(privateKey);

        // anvil provided wallet
        address wallet = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        (bool success, ) = wallet.call{value: 0.3 ether}("");
        require(success, "Failed to send Ether");

        TestNFT nft = new TestNFT(
            "https://media.mulf.wtf/testnft-img.png",
            wallet
        );
        marketplace = new MiniMart(payable(wallet), "MiniMart", "1");

        nft.mint(wallet);
        nft.mint(wallet);

        uint256 currentNonce = marketplace.nonces(wallet);

        MiniMart.Order memory newOrder = MiniMart.Order({
            price: 0.1 ether,
            nftContract: address(nft),
            tokenId: 1,
            seller: wallet,
            expiration: 0,
            nonce: currentNonce
        });

        bytes32 structHash = keccak256(
            abi.encode(
                marketplace.ORDER_TYPEHASH(),
                newOrder.price,
                newOrder.nftContract,
                newOrder.tokenId,
                newOrder.seller,
                newOrder.expiration,
                newOrder.nonce
            )
        );

        bytes32 domainSeparator = marketplace.DOMAIN_SEPARATOR();

        // Manually construct the final digest, replicating what _hashTypedDataV4 does.
        // Formula: keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash))
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 newOrderId = marketplace.addOrder(newOrder, signature);

        console.log("New order sumbitted. Order id: ");
        console.logBytes32(newOrderId);

        MiniMart.Order memory fetchedOrder = marketplace.getOrder(newOrderId);

        console.log("\n--- Fetched Order Details ---");
        console.log("Price:", fetchedOrder.price);
        console.log("NFT Contract:", fetchedOrder.nftContract);
        console.log("Token ID:", fetchedOrder.tokenId);
        console.log("Seller:", fetchedOrder.seller);
        console.log("Expiration:", fetchedOrder.expiration);
        console.log("---------------------------\n");

        vm.stopBroadcast();
    }
}

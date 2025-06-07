// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MiniMart} from "../src/MiniMart.sol";
import {TestNFT} from "../src/TestNFT.sol";

contract DeployLocal is Script {
    MiniMart public marketplace;

    function setUp() public {}

    function run() public {
        vm.createSelectFork("local");

        // DONT PANICK, this is an anvil provided private key
        vm.startBroadcast(
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        );

        // anvil provided wallet
        address wallet = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        (bool success, ) = wallet.call{value: 0.1 ether}("");
        require(success, "Failed to send Ether");

        TestNFT nft = new TestNFT(
            "https://media.mulf.wtf/testnft-img.png",
            wallet
        );
        marketplace = new MiniMart(payable(wallet));

        nft.mint(wallet);
        nft.mint(wallet);

        bytes32 newOrderId = marketplace.addOrder(
            MiniMart.Order({
                price: 0.1 ether,
                nftContract: address(nft),
                tokenId: 1,
                seller: msg.sender,
                expiration: 0
            })
        );

        console.log("New order sumbitted. Order id: ");
        console.logBytes32(newOrderId);

        vm.stopBroadcast();
    }
}

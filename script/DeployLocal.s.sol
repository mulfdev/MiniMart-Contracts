// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {MiniMart} from "../src/MiniMart.sol";
import {TestNFT} from "../src/TestNFT.sol";

contract DeployLocal is Script {
    MiniMart public marketplace;

    function setUp() public {}

    function run() public {
        vm.createSelectFork("local");

        // DONT PANICK, this is an avil provided private key
        vm.startBroadcast(
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        );

        address wallet = vm.envAddress("WALLET_ADDR");

        (bool success, ) = wallet.call{value: 0.1 ether}("");
        require(success, "Failed to send Ether");

        TestNFT nft = new TestNFT(
            "https://media.mulf.wtf/testnft-img.png",
            wallet
        );
        marketplace = new MiniMart(payable(wallet));

        nft.mint(wallet);
        nft.mint(wallet);

        vm.stopBroadcast();
    }
}

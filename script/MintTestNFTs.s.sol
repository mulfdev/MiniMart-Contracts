// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { MiniMart } from "../src/MiniMart.sol";
import { TestNFT } from "../src/TestNFT.sol";

contract MintTestNFTs is Script {
    function run() external {
        vm.createSelectFork("base_sepolia");
        address eoaDeployer = msg.sender;

        TestNFT testNft = TestNFT(0x6E62ab660c7ACD232f17B15b54D8e9F738941cb4);

        for (uint8 i; i <= 5; i++) {
            vm.broadcast(eoaDeployer);
            testNft.mint(0x75A6085Bbc25665B6891EA94475E6120897BA90b);
        }
    }
}

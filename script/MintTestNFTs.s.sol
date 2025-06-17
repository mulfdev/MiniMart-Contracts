// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";
import { MiniMart } from "../src/MiniMart.sol";
import { TestNFT } from "../src/TestNFT.sol";

contract Deploy is Script {
    function run() external {
        vm.createSelectFork("base_sepolia");

        TestNFT testNft = new TestNFT("https://media.mulf.wtf/testnft-img.png");
        for (uint8 i; i < 15; i++) {
            testNft.mint(0x02F9B04A37b089b5887c491097E62D2111c2BB7F);
        }
    }
}

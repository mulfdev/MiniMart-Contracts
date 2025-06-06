// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {MiniMartMarketplace} from "../src/MiniMartMarketplace.sol";

contract CounterScript is Script {
    MiniMartMarketplace public marketplace;

    function setUp() public {}

    function run() public {
        vm.createSelectFork("base_sepolia");
        vm.startBroadcast();

        marketplace = new MiniMartMarketplace(
            payable(0x75A6085Bbc25665B6891EA94475E6120897BA90b)
        );

        vm.stopBroadcast();
    }
}

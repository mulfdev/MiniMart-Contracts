// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {MiniMart} from "../src/MiniMart.sol";

contract CounterScript is Script {
    MiniMart public marketplace;

    function setUp() public {}

    function run() public {
        vm.createSelectFork("local");
        vm.startBroadcast();

        marketplace = new MiniMart(
            payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)
        );

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {TestNFT} from "../src/TestNFT.sol";

contract TestNFTDeploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        new TestNFT("", address(0x75A6085Bbc25665B6891EA94475E6120897BA90b));

        vm.stopBroadcast();
    }
}

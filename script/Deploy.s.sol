// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { ICREATE3Factory } from "create3-factory/src/ICREATE3Factory.sol";
import { MiniMart } from "../src/MiniMart.sol";

contract Deploy is Script {
    ICREATE3Factory constant FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    function run() external {
        vm.createSelectFork("base_sepolia");

        bytes32 salt = keccak256(
            "912362352d3a10fdf1927ae0539d77de8af08223db6d05dd4d9c92f5d406fabfce330fc2c3ff9a49fd1db517b0216c02184dc9625f02077da5551b3f0705a999"
        );
        address eoaDeployer = msg.sender;

        console.log("Deployer (EOA):", eoaDeployer);

        bytes memory initCode =
            abi.encodePacked(type(MiniMart).creationCode, abi.encode(eoaDeployer, "MiniMart", "1"));

        address predicted = FACTORY.getDeployed(eoaDeployer, salt);
        console.log("Predicted Address:", predicted);

        vm.startBroadcast(eoaDeployer);

        address deployed = FACTORY.deploy(salt, initCode);

        vm.stopBroadcast();

        console.log("Deployed Address: ", deployed);
        require(deployed == predicted, "Address Mismatch: The final check failed.");
        console.log("Success! MiniMart deployed to:", deployed);
    }
}

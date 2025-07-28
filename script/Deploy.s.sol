// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { ICREATE3Factory } from "create3-factory/src/ICREATE3Factory.sol";
import { MiniMart } from "../src/MiniMart.sol";

contract Deploy is Script {
    ICREATE3Factory constant FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    function run() external {
        vm.createSelectFork("base");

        bytes32 salt = keccak256("6101591d2e20deddc31e81fa238485c720b8c2f978329f2a55a204522ab34c23");
        address eoaDeployer = msg.sender;

        console.log("Deployer (EOA):", eoaDeployer);

        bytes memory initCode = abi.encodePacked(
            type(MiniMart).creationCode, abi.encode(eoaDeployer, "MiniMart", "1.1")
        );

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

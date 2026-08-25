// script/Deploy.s.sol — forge script template
// Default target: Sepolia (or resolved custom-chain testnet). Mainnet only on explicit request.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol"; // replace with actual contract(s)

contract Deploy is Script {
    function run() external returns (Vault vault) {
        // wallet resolved per scripts/wallet_setup.md — pass --account <keystore-name>,
        // --ledger, or a plaintext key (Anvil-only) on the CLI, never hardcode here.
        vm.startBroadcast();
        vault = new Vault(/* constructor args */);
        vm.stopBroadcast();

        console.log("Deployed Vault at:", address(vault));
    }
}

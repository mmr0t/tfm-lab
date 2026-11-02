// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {SmokeVulnerable, SmokeFixed} from "../src/_smoke/Smoke.sol";

/// @notice Prueba del arnes. Demuestra el patron vulnerable/corregido.
contract SmokeTest is BaseChallenge {
    SmokeVulnerable internal vuln;
    SmokeFixed internal fixedC;

    function setUp() public override {
        super.setUp();
        vm.prank(deployer);
        vuln = new SmokeVulnerable();
        vm.prank(deployer);
        fixedC = new SmokeFixed();
    }

    function test_Exploit_Vulnerable() public {
        assertFalse(vuln.isSolved(), "no debe partir resuelto");
        vm.prank(attacker);
        vuln.capture();
        assertTrue(vuln.isSolved(), "el ataque debe resolver el reto");
    }

    function test_Fixed_Resiste() public {
        vm.prank(attacker);
        vm.expectRevert(bytes("no autorizado"));
        fixedC.capture();
        assertFalse(fixedC.isSolved(), "la version corregida no debe resolverse");
    }
}

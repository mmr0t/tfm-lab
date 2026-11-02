// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {LoteriaVulnerable, AtacanteLoteria} from "../src/C5-aleatoriedad/Vulnerable.sol";
import {LoteriaFixed} from "../src/C5-aleatoriedad/Fixed.sol";

contract C5_Aleatoriedad is BaseChallenge {
    function test_Exploit_Vulnerable() public {
        vm.prank(deployer);
        LoteriaVulnerable loteria = new LoteriaVulnerable{value: 5 ether}();
        assertFalse(loteria.isSolved());

        vm.prank(attacker);
        AtacanteLoteria exploit = new AtacanteLoteria(address(loteria));
        vm.deal(address(exploit), 1 ether);

        // El atacante solo juega cuando la fórmula le da ganador. Avanzamos el
        // tiempo hasta un bloque favorable (modela "espera a que le toque").
        while (!exploit.vaAGanar()) {
            vm.warp(block.timestamp + 1);
        }

        vm.prank(attacker);
        exploit.atacar();

        assertTrue(loteria.isSolved(), "el atacante vacia la loteria");
        assertEq(address(exploit).balance, 6 ether, "se lleva el bote entero (5+1)");
    }

    function test_Fixed_Resiste() public {
        vm.prank(deployer);
        LoteriaFixed loteria = new LoteriaFixed{value: 5 ether}();

        // En el momento de entrar, el blockhash que decidirá el sorteo aún no
        // existe: el atacante no puede calcular si ganará.
        assertEq(blockhash(block.number), bytes32(0), "blockhash del bloque actual no disponible");

        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        loteria.entrar{value: 1 ether}();

        // No hay pago inmediato: tras entrar, el reto NO está resuelto, haga lo
        // que haga el atacante en este bloque.
        assertFalse(loteria.isSolved(), "entrar no paga: no hay exploit de un solo bloque");
        assertEq(address(loteria).balance, 6 ether, "el bote sigue intacto");

        // Tampoco puede sortear en el mismo bloque para "ver y revertir": el
        // sorteo exige que el bloque de compromiso ya esté cerrado.
        vm.expectRevert(bytes("espera al siguiente bloque"));
        loteria.sortear();

        // El sorteo depende del blockhash de un bloque posterior, fuera del
        // control del atacante.
        vm.roll(block.number + 1);
        loteria.sortear();
        // El resultado ya no es una victoria garantizada: depende del blockhash.
    }

    /// @notice La mitigación no introduce un bloqueo: si nadie sortea en 256
    /// bloques, el blockhash caduca y la ronda se libera como perdida.
    function test_Fixed_BlockhashCaducado_NoBloquea() public {
        vm.prank(deployer);
        LoteriaFixed loteria = new LoteriaFixed{value: 5 ether}();

        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        loteria.entrar{value: 1 ether}();

        vm.roll(block.number + loteria.VENTANA() + 1);
        loteria.sortear();

        assertEq(loteria.jugador(), address(0), "la ronda queda libre");
        assertEq(address(loteria).balance, 6 ether, "la apuesta caducada no se devuelve");

        // Otra persona puede volver a jugar.
        vm.prank(user1);
        loteria.entrar{value: 1 ether}();
        assertEq(loteria.jugador(), user1, "la loteria sigue operativa");
    }
}

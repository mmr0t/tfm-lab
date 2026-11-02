// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @title BaseChallenge
/// @notice Base comun para todos los retos del TFM.
///
/// Convencion de cada caso (C1..C10):
///   - `src/CXX-nombre/Vulnerable.sol` y `src/CXX-nombre/Fixed.sol` exponen la
///     misma interfaz, incluida una funcion `isSolved()` que define la condicion
///     de exito del reto (la misma que comprueba Polonio).
///   - El test de cada caso hereda de este contrato y define dos pruebas:
///       * `test_Exploit_Vulnerable()`  -> tras el ataque, isSolved() == true
///       * `test_Fixed_Resiste()`       -> el mismo ataque NO logra isSolved() == true
///
/// Esto materializa el indicador de OE4: el exploit cumple la condicion de exito
/// sobre la version vulnerable y no la cumple sobre la corregida.
abstract contract BaseChallenge is Test {
    // Cuentas estandar del escenario. Se corresponden con las de Polonio:
    //   deployer -> accounts[0] (despliega el reto)
    //   attacker -> accounts[1] (el jugador)
    address internal deployer = makeAddr("deployer");
    address internal attacker = makeAddr("attacker");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");

    function setUp() public virtual {
        vm.deal(deployer, 100 ether);
        vm.deal(attacker, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }
}

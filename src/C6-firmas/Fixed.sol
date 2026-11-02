// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C6 - Versiones corregidas.
// Variante A: EIP-712 (dominio con chainid y address(this)) + nonce + ECDSA.
// Variante B: ECDSA de OpenZeppelin, que rechaza la firma maleable (s alto).

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Variante A corregida: nonce + EIP-712.
/// El nonce impide el replay simple; el dominio EIP-712 (chainid + address(this))
/// impide el replay cross-chain y cross-contract; ECDSA rechaza la maleabilidad.
contract PagosSeguro is EIP712 {
    using ECDSA for bytes32;

    address public firmante;
    mapping(uint256 => bool) public nonceUsado;

    bytes32 private constant TIPO =
        keccak256("Retiro(address to,uint256 amount,uint256 nonce)");

    constructor(address _f) payable EIP712("PagosSeguro", "1") {
        firmante = _f;
    }

    /// @notice Digest EIP-712 que el firmante debe firmar.
    function digest(address to, uint256 amount, uint256 nonce) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(TIPO, to, amount, nonce)));
    }

    function retirar(address to, uint256 amount, uint256 nonce, bytes calldata sig) external {
        require(!nonceUsado[nonce], "firma ya usada");
        nonceUsado[nonce] = true;

        require(digest(to, amount, nonce).recover(sig) == firmante, "firma invalida");
        payable(to).transfer(amount);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante B corregida: ECDSA rechaza el s alto.
/// Mantiene el registro por firma, pero usa `ECDSA.recover`, que revierte ante
/// una firma con s en la mitad alta de la curva (la gemela maleable).
contract PagosMaleableFixed {
    using ECDSA for bytes32;

    address public firmante;
    mapping(bytes32 => bool) public firmaUsada;

    constructor(address _f) payable {
        firmante = _f;
    }

    function retirar(address to, uint256 amount, bytes calldata sig) external {
        bytes32 idFirma = keccak256(sig);
        require(!firmaUsada[idFirma], "firma usada");
        firmaUsada[idFirma] = true;

        bytes32 hash = keccak256(abi.encodePacked(to, amount));
        require(hash.recover(sig) == firmante, "firma invalida"); // revierte si s es alto
        payable(to).transfer(amount);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

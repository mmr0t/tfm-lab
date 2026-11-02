// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C10 - Versiones corregidas.
// Variante A: comprobar los límites del índice (acceso normal a arrays en 0.8,
//             que ya revierte fuera de rango) en lugar de aritmética de slots.
// Variante B: usar abi.encode (con padding y longitudes) en vez de encodePacked,
//             de modo que dos reparticiones distintas dan hashes distintos.

contract BovedaFixed {
    address public owner; // slot 0
    uint256[] public registros; // slot 1
    address public immutable desplegador;

    constructor() {
        owner = msg.sender;
        desplegador = msg.sender;
    }

    function anotar(uint256 valor) external {
        registros.push(valor);
    }

    // El acceso indexado normal revierte si el índice está fuera de rango.
    function editar(uint256 indice, uint256 valor) external {
        require(indice < registros.length, "fuera de rango");
        registros[indice] = valor;
    }

    function isSolved() external view returns (bool) {
        return owner != desplegador;
    }
}

contract PermisosFixed {
    address public firmante;

    constructor(address _f) {
        firmante = _f;
    }

    function esAdmin(
        address[] calldata admins,
        address[] calldata users,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external view returns (bool) {
        // abi.encode incluye longitudes: no hay ambigüedad entre los dos arrays.
        bytes32 hash = keccak256(abi.encode(admins, users));
        return ecrecover(hash, v, r, s) == firmante;
    }
}

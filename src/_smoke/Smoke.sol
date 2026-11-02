// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso de humo. NO forma parte del catalogo C1..C10.
// Su unico proposito es demostrar que el arnes de pruebas del laboratorio
// funciona: un ataque tiene exito contra la version vulnerable y fracasa
// contra la corregida.

/// @notice Version vulnerable: `capture()` no comprueba quien llama.
contract SmokeVulnerable {
    address public owner;
    bool public captured;

    constructor() {
        owner = msg.sender;
    }

    function capture() external {
        captured = true;
    }

    /// @notice Condicion de exito del reto.
    function isSolved() external view returns (bool) {
        return captured;
    }
}

/// @notice Version corregida: solo el `owner` puede capturar.
contract SmokeFixed {
    address public owner;
    bool public captured;

    constructor() {
        owner = msg.sender;
    }

    function capture() external {
        require(msg.sender == owner, "no autorizado");
        captured = true;
    }

    function isSolved() external view returns (bool) {
        return captured;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C3 - Versiones corregidas.
// Variante A: patrón pull (cada usuario retira su reembolso por separado).
// Variante B: comprobar el valor de retorno y revertir si falla.

/// @notice Variante A corregida: patrón pull.
/// La subasta no empuja los reembolsos: los apunta para que cada postor los
/// retire en una transacción propia. El fallo de un usuario solo le afecta a él,
/// así que un postor malicioso ya no puede congelar la subasta.
contract SubastaFixed {
    address public mejorPostor;
    uint256 public mejorPuja;
    mapping(address => uint256) public reembolsos;

    function pujar() external payable {
        require(msg.value > mejorPuja, "puja baja");

        if (mejorPostor != address(0)) {
            reembolsos[mejorPostor] += mejorPuja; // se apunta, no se envía
        }

        mejorPostor = msg.sender;
        mejorPuja = msg.value;
    }

    function retirarReembolso() external {
        uint256 amount = reembolsos[msg.sender];
        require(amount > 0, "nada que retirar");
        reembolsos[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "fallo");
    }
}

/// @notice Variante B corregida.
/// Se comprueba el retorno de la llamada de bajo nivel y se revierte si falla,
/// de modo que el estado no se da por consumado si el envío no ocurrió.
contract RecompensasFixed {
    mapping(address => uint256) public pendiente;

    function asignar(address a) external payable {
        pendiente[a] += msg.value;
    }

    function reclamar() external {
        uint256 amount = pendiente[msg.sender];
        require(amount > 0, "nada pendiente");

        pendiente[msg.sender] = 0;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transferencia fallida"); // revierte y restablece el estado
    }
}

/// @notice Variante C corregida: reparto en dos fases con patrón pull.
/// `repartir` solo fija la cuota por participante (coste constante) y cada
/// participante la retira por su cuenta. Ninguna operación recorre la lista, así
/// que su longitud ya no afecta al gas de nadie. Un participante registrado
/// varias veces cobra una cuota por registro, como en la versión vulnerable.
contract RepartoFixed {
    address public organizador;
    uint256 public numParticipantes;
    mapping(address => uint256) public registros;
    uint256 public cuota;
    bool public repartido;

    constructor() payable {
        organizador = msg.sender;
    }

    function registrar(address p) external {
        require(!repartido, "cerrado");
        registros[p] += 1;
        numParticipantes += 1;
    }

    function repartir() external {
        require(msg.sender == organizador, "solo organizador");
        require(!repartido, "ya repartido");
        cuota = address(this).balance / numParticipantes;
        repartido = true;
    }

    function reclamar() external {
        require(repartido, "aun no");
        uint256 amount = cuota * registros[msg.sender];
        require(amount > 0, "nada que reclamar");
        registros[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "fallo");
    }
}

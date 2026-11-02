// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C3 - Llamadas externas no comprobadas y denegación de servicio.
// OWASP SC06 (llamadas no comprobadas) y SC10/mención (DoS). SWC-104, SWC-113.
// Variante A: DoS por revert en una llamada externa dentro del patrón push.
// Variante B: valor de retorno de una llamada de bajo nivel ignorado.

/// @notice Variante A: DoS por reembolso "push".
/// La subasta devuelve la puja al postor anterior con `transfer`. Si ese postor
/// es un contrato que rechaza el Ether, el reembolso revierte y nadie puede
/// volver a pujar: la subasta queda congelada con el atacante como ganador.
contract SubastaVulnerable {
    address public mejorPostor;
    uint256 public mejorPuja;

    function pujar() external payable {
        require(msg.value > mejorPuja, "puja baja");

        // FALLO: si el postor anterior rechaza el Ether, este reembolso revierte
        // y bloquea toda la subasta (patrón push).
        if (mejorPostor != address(0)) {
            payable(mejorPostor).transfer(mejorPuja);
        }

        mejorPostor = msg.sender;
        mejorPuja = msg.value;
    }
}

/// @notice Variante B: valor de retorno ignorado (SC06, SWC-104).
/// `reclamar` pone la recompensa a cero y envía con `send`, pero no comprueba el
/// retorno. Si el envío falla, la función no revierte: el usuario pierde su
/// recompensa y el registro de la deuda.
contract RecompensasVulnerable {
    mapping(address => uint256) public pendiente;

    function asignar(address a) external payable {
        pendiente[a] += msg.value;
    }

    function reclamar() external {
        uint256 amount = pendiente[msg.sender];
        require(amount > 0, "nada pendiente");

        pendiente[msg.sender] = 0;

        // FALLO: no se comprueba el retorno de send. Fallo silencioso.
        payable(msg.sender).send(amount);
    }
}

/// @notice Variante C: bucle no acotado (DoS por límite de gas, SWC-128).
/// `repartir` recorre todos los participantes y envía a cada uno su parte en una
/// sola transacción. El coste crece linealmente con la lista y la lista la puede
/// alargar cualquiera, porque registrarse es gratuito y no tiene límite. Cuando
/// el recorrido supera el gas máximo de un bloque, la función ya no puede
/// ejecutarse nunca y el bote queda bloqueado.
contract RepartoVulnerable {
    address public organizador;
    address[] public participantes;
    bool public repartido;

    constructor() payable {
        organizador = msg.sender;
    }

    function registrar(address p) external {
        require(!repartido, "cerrado");
        participantes.push(p); // FALLO: crecimiento sin cota controlado por terceros
    }

    function numParticipantes() external view returns (uint256) {
        return participantes.length;
    }

    function repartir() external {
        require(msg.sender == organizador, "solo organizador");
        require(!repartido, "ya repartido");
        uint256 parte = address(this).balance / participantes.length;
        // FALLO: un envío por participante en la misma transacción.
        for (uint256 i = 0; i < participantes.length; i++) {
            payable(participantes[i]).transfer(parte);
        }
        repartido = true;
    }
}

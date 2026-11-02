// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C1 - Control de acceso (OWASP SC01).
// Dos variantes del mismo fallo: una funcion que cambia estado critico sin
// comprobar quien llama, y una autorizacion basada en tx.origin.

/// @notice Variante A: función desprotegida.
/// `setOwner` cambia al propietario sin ningún control de acceso, de modo que
/// la protección de `withdrawAll` deja de servir: cualquiera se nombra owner y
/// vacía la bóveda. Es la forma más pura de SC01 (SWC-105 / SWC-100).
contract BovedaVulnerable {
    address public owner;

    constructor() payable {
        owner = msg.sender;
    }

    function deposit() external payable {}

    // FALLO: sin control de acceso. Cualquiera puede apropiarse del contrato.
    function setOwner(address newOwner) external {
        owner = newOwner;
    }

    function withdrawAll() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice Condición de éxito: la bóveda ha quedado vacía.
    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante B: autorización por `tx.origin` (SWC-115).
/// Autoriza la transferencia comprobando `tx.origin` en vez de `msg.sender`,
/// lo que permite un ataque de phishing: un contrato intermedio actúa en nombre
/// de la víctima y la comprobación sigue pasando.
contract WalletTxOriginVulnerable {
    address public owner;

    constructor() payable {
        owner = msg.sender;
    }

    receive() external payable {}

    function transfer(address payable to, uint256 amount) external {
        // FALLO: tx.origin es la EOA que originó la transacción, no quien llama.
        require(tx.origin == owner, "no autorizado");
        to.transfer(amount);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante C: inicialización desprotegida.
/// Patrón habitual en contratos que se despliegan detrás de un proxy o con
/// fábricas: el propietario no se fija en el constructor sino en `initialize`.
/// La función no comprueba quién la llama ni si ya se ejecutó, así que cualquiera
/// puede invocarla (antes o después del despliegue legítimo) y nombrarse owner.
/// Es el fallo del primer incidente de Parity (julio de 2017).
contract BovedaInicializableVulnerable {
    address public owner;

    // FALLO: sin control de acceso y sin marca de "ya inicializado".
    function initialize(address _owner) external {
        owner = _owner;
    }

    function deposit() external payable {}

    function withdrawAll() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

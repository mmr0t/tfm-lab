// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C10 - Validación de entradas (OWASP SC05).
// Variante A: escritura en posición de almacenamiento arbitraria (SWC-124).
// Variante B: colisión de hash con abi.encodePacked sobre dos arrays dinámicos (SWC-133).

/// @notice Variante A: escritura arbitraria de storage.
/// `editar` calcula el slot destino con un índice del usuario sin comprobar
/// límites. Con el índice adecuado, el destino se desborda (módulo 2^256) y
/// aterriza en el slot 0, sobrescribiendo `owner`.
contract BovedaVulnerable {
    address public owner; // slot 0 (objetivo)
    uint256[] public registros; // slot 1
    address public immutable desplegador;

    constructor() {
        owner = msg.sender;
        desplegador = msg.sender;
    }

    function anotar(uint256 valor) external {
        registros.push(valor);
    }

    // FALLO: sstore en registros[indice] sin bounds check.
    function editar(uint256 indice, uint256 valor) external {
        assembly {
            mstore(0x00, registros.slot)
            let base := keccak256(0x00, 0x20)
            sstore(add(base, indice), valor)
        }
    }

    /// @notice Condición de éxito: la propiedad ha cambiado de manos.
    function isSolved() external view returns (bool) {
        return owner != desplegador;
    }
}

/// @notice Variante B: colisión de hash con encodePacked.
/// Valida una firma sobre dos arrays dinámicos concatenados con encodePacked, que
/// no marca dónde acaba uno y empieza el otro: el atacante recompone los arrays
/// (mueve su dirección de `users` a `admins`) sin cambiar el hash ni la firma.
contract PermisosVulnerable {
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
        bytes32 hash = keccak256(abi.encodePacked(admins, users));
        return ecrecover(hash, v, r, s) == firmante;
    }
}

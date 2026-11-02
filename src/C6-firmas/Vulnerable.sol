// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C6 - Firmas (OWASP mención, SWC-121 replay, SWC-117 maleabilidad).
// Variante A: firma sin nonce ni dominio -> reutilizable (replay).
// Variante B: anti-replay ingenuo por hash de la firma -> evadible por maleabilidad.

/// @notice Variante A: replay.
/// El mensaje solo contiene (to, amount): sin nonce, sin address(this), sin
/// chainid. Nada marca la firma como usada, así que se puede reenviar N veces.
contract PagosVulnerable {
    address public firmante;

    constructor(address _f) payable {
        firmante = _f;
    }

    function retirar(address to, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 hash = keccak256(abi.encodePacked(to, amount));
        require(ecrecover(hash, v, r, s) == firmante, "firma invalida");
        payable(to).transfer(amount);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante B: maleabilidad.
/// Intenta evitar el replay registrando cada firma por el hash de (v, r, s). Pero
/// `ecrecover` acepta también la firma "gemela" (s' = n - s, v invertida), que
/// tiene otro hash: el guard no la reconoce como usada y el pago se repite.
contract PagosMaleableVulnerable {
    address public firmante;
    mapping(bytes32 => bool) public firmaUsada;

    constructor(address _f) payable {
        firmante = _f;
    }

    function retirar(address to, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 idFirma = keccak256(abi.encodePacked(v, r, s));
        require(!firmaUsada[idFirma], "firma usada");
        firmaUsada[idFirma] = true;

        bytes32 hash = keccak256(abi.encodePacked(to, amount));
        require(ecrecover(hash, v, r, s) == firmante, "firma invalida");
        payable(to).transfer(amount);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

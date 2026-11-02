// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C2 - Reentrada (OWASP SC08, SWC-107).
// Variante A: reentrada clásica por violar Checks-Effects-Interactions.
// Variante B: reentrada de solo lectura sobre una función view consumida como oráculo.

/// @notice Variante A: reentrada clásica.
/// `withdraw` hace la llamada externa ANTES de poner el saldo a cero, así que el
/// receptor puede reentrar mientras su saldo registrado sigue intacto.
contract BancoVulnerable {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "sin fondos");

        // INTERACTION antes que EFFECT: punto de reentrada.
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transferencia fallida");

        balances[msg.sender] = 0;
    }

    /// @notice Condición de éxito: el banco ha quedado vacío.
    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante B: reentrada de solo lectura.
/// `withdraw` está protegido con un guard propio, pero cede el control antes de
/// recalcular `totalShares`. La función view `pricePerShare`, que otros contratos
/// consumen como oráculo, no lleva guard y puede leerse en ese instante
/// inconsistente (el balance ya bajó, pero totalShares no).
contract PoolVulnerable {
    uint256 private _locked = 1;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    modifier nonReentrant() {
        require(_locked == 1, "reentrada");
        _locked = 2;
        _;
        _locked = 1;
    }

    function deposit() external payable {
        uint256 minted = totalShares == 0
            ? msg.value
            : (msg.value * totalShares) / (address(this).balance - msg.value);
        shares[msg.sender] += minted;
        totalShares += minted;
    }

    function withdraw(uint256 amount) external nonReentrant {
        uint256 value = (amount * address(this).balance) / totalShares;
        shares[msg.sender] -= amount;

        // Cede el control con totalShares aún sin actualizar.
        (bool ok, ) = msg.sender.call{value: value}("");
        require(ok, "fallo");

        totalShares -= amount; // estado inconsistente hasta aquí
    }

    // Oráculo consumido por terceros. NO lleva guard (es view).
    function pricePerShare() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return (address(this).balance * 1e18) / totalShares;
    }
}

/// @notice Variante C: reentrada entre funciones (cross-function).
/// `withdraw` lleva un guard, pero solo protege a la propia función. Durante la
/// llamada externa el saldo del usuario sigue sin descontar, y `transfer`, que
/// lee y escribe ese mismo saldo, no tiene guard. El receptor reentra en
/// `transfer` y mueve a otra cuenta un saldo que está a punto de retirar: el
/// mismo Ether se cobra dos veces. Muestra que un guard aislado no sustituye a
/// Checks-Effects-Interactions.
contract BancoTransferibleVulnerable {
    mapping(address => uint256) public balances;
    uint256 private _locked = 1;

    modifier nonReentrant() {
        require(_locked == 1, "reentrada");
        _locked = 2;
        _;
        _locked = 1;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    // FALLO: sin guard y sobre el mismo estado que withdraw.
    function transfer(address to, uint256 amount) external {
        require(balances[msg.sender] >= amount, "saldo insuficiente");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "sin fondos");

        // INTERACTION antes que EFFECT: el saldo aún es visible para transfer.
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transferencia fallida");

        balances[msg.sender] = 0;
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

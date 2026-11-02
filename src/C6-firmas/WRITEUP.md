# C6. Firmas: writeup

Este documento explica cómo resolver el reto del caso C6 y las otras variantes que se estudian en el laboratorio. El análisis completo está en la sección 4.6 de la memoria.

## El reto: La Firma Reutilizable

En Polonio el reto se llama `FirmaReutilizable`. En el laboratorio, el contrato equivalente es `PagosVulnerable` (`src/C6-firmas/Vulnerable.sol`).

**Escenario.** Un contrato de pagos guarda 3 ETH. Solo paga cuando se le presenta una firma de una cuenta autorizada (`firmante`) que aprueba el pago. El reto te entrega una firma que autoriza **1 ETH** a tu cuenta:

```
to     = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8   (tu cuenta, accounts[1])
amount = 1000000000000000000                           (1 ETH)
v      = 28
r      = 0x348fe8bd903828cd8629fe21b7786d9c8b9fd90f9c7fd8795a2657f59e78f491
s      = 0x1d19ae5923e221ef33a54baf8130f826fc39de0034cc23a70ca843ccfe230eb4
```

**Objetivo.** Vaciar los 3 ETH del contrato con esa única autorización de 1 ETH. El reto se da por resuelto cuando `isSolved()` devuelve `true`.

## La vulnerabilidad

```solidity
function retirar(address to, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
    bytes32 hash = keccak256(abi.encodePacked(to, amount));
    require(ecrecover(hash, v, r, s) == firmante, "firma invalida");
    payable(to).transfer(amount);
}
```

`ecrecover` obtiene la dirección que firmó el mensaje y el contrato comprueba que sea la autorizada. Eso demuestra **quién** aprobó el pago, pero no **cuántas veces** ni **dónde** puede usarse la firma. Eso depende de lo que contenga el mensaje y de lo que registre el contrato, y aquí faltan tres cosas:

- No hay ningún *nonce*, un número de un solo uso que distinga una autorización de otra.
- El contrato no anota qué firmas ya se han usado.
- El mensaje no incluye ni la dirección del contrato ni el identificador de la cadena.

La misma firma vale, por tanto, tantas veces como se presente.

## Resolución paso a paso

1. **Comprobar la firma.** Llama a `retirar` con los cinco valores entregados. Recibes 1 ETH y el contrato queda con 2 ETH.
2. **Presentarla otra vez.** Repite exactamente la misma llamada. Como el contrato no recuerda haber pagado, vuelve a aceptar la firma. Quedan 1 ETH.
3. **Una tercera vez.** El contrato queda a 0.
4. **Verificar.** `isSolved()` devuelve `true`.

No necesitas la clave privada del firmante: la firma es pública en cuanto se usa una vez, porque viaja en los datos de la transacción.

## Otras variantes del caso

**Reutilización en otro contrato.** Si otro contrato confía en el mismo firmante, la firma emitida para el primero vale también en el segundo, porque nada en el mensaje los distingue. Lo mismo ocurre con otra cadena, por ejemplo una bifurcación de la red. Es lo que pasó en el puente Omni sobre EthereumPoW en 2022.

**Maleabilidad** (`PagosMaleableVulnerable`). Este contrato intenta evitar la reutilización anotando cada firma por el hash de sus bytes `(v, r, s)`. El problema es que una firma ECDSA tiene una gemela igual de válida: si `(r, s)` firma un mensaje, `(r, n - s)` con el valor de `v` contrario también lo firma, siendo `n` el orden del grupo de la curva secp256k1. La gemela tiene otros bytes, el registro no la reconoce y el contrato paga dos veces. Para la firma del reto, la gemela sería:

```
v' = 27
s' = n - s = 0xe2e651a6dc1dde10cc5ab4507ecf07d7be74fee67a7c7c94b32a1abfd213328d
n  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
```

Se construye solo con valores públicos: no hace falta ninguna clave.

## Mitigación

La versión corregida (`src/C6-firmas/Fixed.sol`) combina tres medidas:

```solidity
bytes32 private constant TIPO =
    keccak256("Retiro(address to,uint256 amount,uint256 nonce)");

function retirar(address to, uint256 amount, uint256 nonce, bytes calldata sig) external {
    require(!nonceUsado[nonce], "firma ya usada");
    nonceUsado[nonce] = true;

    require(digest(to, amount, nonce).recover(sig) == firmante, "firma invalida");
    payable(to).transfer(amount);
}
```

1. **Nonce.** Forma parte del mensaje firmado y se marca como usado antes de pagar. Cada firma solo vale una vez.
2. **EIP-712.** El mensaje firmado incluye un dominio con el nombre y la versión de la aplicación, el identificador de la cadena y la dirección del contrato. La firma queda atada a un contrato y a una cadena concretos. La implementación de OpenZeppelin recalcula el dominio si cambia el identificador de la cadena.
3. **ECDSA de OpenZeppelin.** Rechaza las firmas con `s` en la mitad alta de la curva, es decir, las gemelas maleables.

Como defensa en profundidad, conviene incluir también en el mensaje una fecha de caducidad y, sobre todo, el beneficiario, para que quien se adelante a presentar una firma ajena no pueda desviar los fondos.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C6_Firmas
./forge test --match-contract C6_Firmas --match-test test_Exploit_Maleabilidad_Vulnerable -vvvv
```

| Variante | Ataque | Mitigación |
|---|---|---|
| Reutilización en el mismo contrato | `test_Exploit_Vulnerable` | `test_Fixed_Resiste` |
| Reutilización en otro contrato o cadena | `test_Exploit_ReplayOtroContrato_Vulnerable` | `test_Fixed_Dominio_Resiste` |
| Maleabilidad | `test_Exploit_Maleabilidad_Vulnerable` | `test_Fixed_Maleabilidad_Resiste` |

`test_Fixed_Dominio_Resiste` cambia el identificador de la cadena con `vm.chainId` para simular una bifurcación y comprueba que la firma deja de valer.

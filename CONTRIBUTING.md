# Contribuir a Palisade

Proponga cambios acotados y explique el flujo afectado, las unidades, los
redondeos y las transiciones de estado. Para modificaciones de precio,
rendimiento, titularidad o roles, adjunte pruebas que cubran el caso normal,
el límite y el rechazo esperado. No incluya claves, direcciones privadas ni
datos de terceros en fixtures.

```bash
bash scripts/ci.sh
```

El PR debe pasar formato, compilación y Foundry tests. Documente cambios de
interfaces y eventos, y revise el impacto sobre las guías de `docs/`.
Reporte cuestiones de seguridad por el canal coordinado descrito en
[SECURITY.md](SECURITY.md), no mediante una issue pública.

-- ============================================================
-- Proyecto: Análisis de Operaciones y Logística
-- Dataset: DataCo Smart Supply Chain Dataset
-- Herramienta: SQLite (DB Browser for SQLite)
-- Autora: Valentina Guaqueta Reyes
-- ============================================================


-- ============================================================
-- FASE 1: EXPLORACIÓN INICIAL
-- ============================================================

-- Total de registros en la base
SELECT COUNT(*) AS total_registros FROM supply_chain_data;
-- Resultado: 180,519 registros

-- Rango de días de envío real
SELECT MIN("Days for shipping (real)"), MAX("Days for shipping (real)") FROM supply_chain_data;
-- Resultado: entre 0 y 6 días

-- Estados de entrega posibles
SELECT DISTINCT "Delivery Status" FROM supply_chain_data;
-- Resultado: Advance shipping, Late delivery, Shipping on time, Shipping canceled

-- Países de cliente (ojo: esta columna NO representa el destino del envío,
-- solo tiene EE.UU. y Puerto Rico. Para geografía real de envío usar "Order Country")
SELECT DISTINCT "Customer Country" FROM supply_chain_data LIMIT 20;


-- ============================================================
-- FASE 2: CALIDAD Y ESTRUCTURA DE LOS DATOS
-- ============================================================

-- ¿Hay pedidos "duplicados"? (Order Id repetido)
-- Hallazgo: no son duplicados por error. Cada fila es un ITEM dentro de una
-- orden, no una orden completa. Un mismo Order Id se repite una vez por cada
-- producto distinto en esa orden. Para contar órdenes reales, usar
-- COUNT(DISTINCT "Order Id"), no COUNT(*).
SELECT "Order Id", COUNT(*) AS repeticiones
FROM supply_chain_data
GROUP BY "Order Id"
HAVING COUNT(*) > 1
LIMIT 20;

-- Revisión de valores nulos en campos clave
SELECT COUNT(*) AS total,
       SUM(CASE WHEN "Customer Id" IS NULL THEN 1 ELSE 0 END) AS sin_cliente,
       SUM(CASE WHEN Sales IS NULL THEN 1 ELSE 0 END) AS sin_ventas
FROM supply_chain_data;
-- Resultado: sin valores nulos en estos campos

-- Consistencia entre Delivery Status y Late_delivery_risk
SELECT "Delivery Status", Late_delivery_risk, COUNT(*) AS Count
FROM supply_chain_data
GROUP BY "Delivery Status", Late_delivery_risk
ORDER BY "Delivery Status";
-- Resultado: consistencia perfecta. Late_delivery_risk = 1 corresponde
-- exactamente a Delivery Status = "Late delivery". Todo lo demás = 0.

-- Validación en detalle: ¿los "duplicados" de Order Id son productos
-- distintos o filas repetidas por error?
SELECT "Order Id", "Order Item Cardprod Id", "Product Name", "Order Item Quantity", "Sales"
FROM supply_chain_data
WHERE "Order Id" IN (2, 4, 5, 7, 8, 9, 10, 11)
ORDER BY "Order Id";

-- Verificación sistemática con ROW_NUMBER: se particiona por Order Id +
-- producto + cantidad + venta. Si dos filas coinciden en todos estos campos,
-- la segunda recibe fila_numero >= 2 (posible duplicación real).
SELECT *,
       ROW_NUMBER() OVER (
           PARTITION BY "Order Id", "Order Item Cardprod Id", "Order Item Quantity", "Sales"
           ORDER BY "Order Id"
       ) AS fila_numero
FROM supply_chain_data
WHERE "Order Id" IN (2, 4, 5, 7, 8, 9, 10, 11)
ORDER BY "Order Id", fila_numero;
-- Hallazgo: algunas combinaciones de Order Id + producto + cantidad + venta
-- SÍ se repiten (ej. Order Id 10 con Cardprod Id 1073 aparece 2 veces,
-- Order Id 11 con Cardprod Id 1014 aparece 2 veces), recibiendo fila_numero = 2.
-- Sin embargo, al revisar el detalle completo de esas filas, se confirma que
-- NO son duplicados por error: el "Order Item Id" (verdadero identificador
-- único de cada línea de pedido) es distinto en cada caso, y el descuento
-- aplicado ("Order Item Discount") también varía. Esto indica que un mismo
-- cliente puede pedir el mismo producto más de una vez dentro de la misma
-- orden, como líneas de pedido separadas y legítimas, cada una con su propio
-- descuento — no una fila repetida por error de carga.

-- Verificación final: ¿existe algún Order Item Id repetido? (la verdadera
-- llave única de cada línea de pedido). Si esto da 0 filas, confirma que
-- no hay duplicados reales de datos.
SELECT "Order Item Id", COUNT(*) AS repeticiones
FROM supply_chain_data
GROUP BY "Order Item Id"
HAVING COUNT(*) > 1;

-- Nota metodológica: al filtrar por "Order Id repetido" (arriba), el
-- Order Id = 1 no aparecía en el resultado, lo que en un primer momento
-- pareció sugerir un hueco en los datos. Se confirmó en Browse Data que el
-- registro sí existe: es una orden de un solo ítem, por lo que el filtro
-- HAVING COUNT(*) > 1 lo excluía correctamente (no un problema de datos).


-- ============================================================
-- FASE 3: HALLAZGOS DE NEGOCIO
-- ============================================================

-- 3.1 Distribución general de entregas (% del total)
SELECT "Delivery Status", COUNT(*) AS total,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM supply_chain_data), 2) AS porcentaje
FROM supply_chain_data
GROUP BY "Delivery Status"
ORDER BY total DESC;
-- Hallazgo clave: 54.8% de los registros son "Late delivery"

-- 3.2 Top países por volumen de órdenes (destino real del envío)
SELECT "Order Country", COUNT(*) AS Count
FROM supply_chain_data
GROUP BY "Order Country"
ORDER BY Count DESC
LIMIT 20;
-- Top 6: Estados Unidos, Francia, México, Alemania, Australia, Brasil

-- 3.3 Modo de envío vs. estado de entrega, con % dentro de cada modo
-- Se usa una window function (SUM(...) OVER PARTITION BY) para calcular
-- el % de cada Delivery Status dentro de su propio Shipping Mode
-- (no sobre el total general de la tabla).
SELECT "Shipping Mode", "Delivery Status", COUNT(*) AS Count,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY "Shipping Mode"), 2) AS porcentaje
FROM supply_chain_data
GROUP BY "Shipping Mode", "Delivery Status"
ORDER BY "Shipping Mode", Count DESC;
-- Hallazgo clave (contraintuitivo): "First Class" tiene la PEOR tasa de
-- cumplimiento (95.32% late delivery), muy por encima de "Standard Class"
-- (38.07%). Hipótesis: los plazos prometidos en First Class son
-- estructuralmente más difíciles de cumplir. Pendiente de confirmar con
-- la diferencia entre días reales y programados (ver 3.5).

-- 3.4 Mercado con mayor % de entregas tardías
-- Se usa CASE WHEN dentro de SUM (agregación condicional) en vez de filtrar
-- con WHERE, porque se necesita mantener el total de cada mercado como
-- denominador para poder calcular el % correctamente.
SELECT Market,
       COUNT(*) AS total_ordenes,
       SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) AS ordenes_tardias,
       ROUND(100.0 * SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_tardias
FROM supply_chain_data
GROUP BY Market
ORDER BY pct_tardias DESC;
-- Hallazgo: el % de entregas tardías es prácticamente uniforme entre
-- mercados (54.36%-55.21%, menos de 1 punto porcentual de diferencia).
-- Esto indica que el problema NO está concentrado geográficamente, sino que
-- es sistémico -> refuerza el hallazgo de 3.3/3.5 (la causa está ligada al
-- modo de envío, no a la región). En volumen absoluto, Europa (27,743) y
-- LATAM (28,044) concentran el mayor número de órdenes tardías por ser los
-- mercados más grandes -> mayor impacto potencial de una solución ahí.

-- 3.5 Confirmación de causa raíz: días programados vs. reales
-- Primero, por modo de envío en general:
SELECT "Shipping Mode",
       ROUND(AVG("Days for shipment (scheduled)"), 2) AS dias_programados_prom,
       ROUND(AVG("Days for shipping (real)"), 2) AS dias_reales_prom,
       ROUND(AVG("Days for shipping (real)" - "Days for shipment (scheduled)"), 2) AS atraso_promedio
FROM supply_chain_data
GROUP BY "Shipping Mode"
ORDER BY atraso_promedio DESC;
-- Hallazgo: First Class y Second Class tardan en promedio el DOBLE de lo
-- prometido (no es un problema de tiempos largos, sino de plazos poco
-- realistas). Standard Class cumple casi exactamente lo prometido.

-- Luego, cruzando Región + Modo de envío, para descartar que el atraso
-- dependa de la geografía y no solo del modo de envío:
SELECT "Order Region", "Shipping Mode",
       ROUND(AVG("Days for shipping (real)" - "Days for shipment (scheduled)"), 2) AS atraso_promedio
FROM supply_chain_data
GROUP BY "Order Region", "Shipping Mode"
ORDER BY "Shipping Mode", atraso_promedio DESC;
-- Hallazgo: dentro de un mismo Shipping Mode, el atraso promedio es
-- consistente entre TODAS las regiones (ej. First Class ronda 1.0 en las
-- 23 regiones, sin importar el tamaño del mercado). Esto confirma que el
-- atraso depende del modo de envío, no de la geografía. Las pequeñas
-- diferencias vistas antes por Market/Region (0.58-0.65 en el punto 3.4)
-- se explican simplemente por el mix distinto de modos de envío que usa
-- cada región, no por un factor geográfico real.

-- 3.6 Verificación de variabilidad: ¿el atraso de First Class es una
-- tendencia estadística o una regla fija del dataset?
SELECT "Shipping Mode",
       MIN("Days for shipping (real)" - "Days for shipment (scheduled)") AS atraso_min,
       MAX("Days for shipping (real)" - "Days for shipment (scheduled)") AS atraso_max,
       COUNT(DISTINCT "Days for shipping (real)" - "Days for shipment (scheduled)") AS valores_distintos
FROM supply_chain_data
GROUP BY "Shipping Mode";
-- Hallazgo clave: "First Class" tiene atraso_min = atraso_max = 1 y un solo
-- valor distinto en las 180,519 filas -> CONFIRMADO: el atraso de First
-- Class no es una tendencia con variabilidad natural, es una regla FIJA y
-- determinística del dataset (siempre exactamente 1 día de atraso). En
-- contraste, Second Class (0 a 4, 5 valores distintos) y Standard Class
-- (-2 a 2, 5 valores distintos, incluye entregas anticipadas) sí muestran
-- variabilidad realista. Same Day tiene poca variación (0 a 1, 2 valores).
-- Conclusión metodológica: el hallazgo de causa raíz de First Class sigue
-- siendo válido dentro del dataset, pero se documenta con la salvedad de
-- que probablemente refleja una regla de generación sintética y no
-- variabilidad orgánica de una operación real -- a diferencia de Second
-- Class y Standard Class, cuyo comportamiento sí luce más realista.

-- 3.7 Categorías de producto con mayor % de atraso
SELECT "Category Name",
       COUNT(*) AS total_ordenes,
       SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) AS ordenes_tardias,
       ROUND(100.0 * SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_tardias
FROM supply_chain_data
GROUP BY "Category Name"
ORDER BY pct_tardias DESC;
-- Hallazgo: las categorías con % más extremo (ej. Golf Bags & Carts, 68.85%)
-- tienen volumen muy bajo (61 órdenes) -> no son estadísticamente
-- representativas, es ruido de muestra pequeña, no una señal de negocio real.
-- Al reordenar por volumen (total_ordenes DESC), la categoría con más
-- órdenes (Cleats, 24,551) tiene un % de atraso de 54.97% -- prácticamente
-- idéntico al promedio general del dataset (54.8%, ver 3.1). Conclusión:
-- el atraso NO se concentra en ninguna categoría de producto específica.
-- Este es el tercer corte (junto con Market/Region en 3.4-3.5) que confirma
-- que el problema es sistémico y transversal a toda la operación, no
-- aislado en un segmento particular del negocio.

-- 3.8 Relación entre Product Status (disponibilidad) y atraso -- DESCARTADA
SELECT "Product Status",
       COUNT(*) AS total_ordenes,
       SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) AS ordenes_tardias,
       ROUND(100.0 * SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_tardias
FROM supply_chain_data
GROUP BY "Product Status";
-- Resultado: "Product Status" = 0 en el 100% de las 180,519 filas (sin
-- variación). No hay comparación posible -> pregunta descartada, la columna
-- no aporta información útil para este dataset (probablemente porque solo
-- se registraron productos disponibles al momento del pedido).

-- 3.9 Rentabilidad (Order Profit Per Order) vs. riesgo de atraso
SELECT Late_delivery_risk,
       COUNT(*) AS total_ordenes,
       ROUND(AVG("Order Profit Per Order"), 2) AS ganancia_promedio,
       ROUND(SUM("Order Profit Per Order"), 2) AS ganancia_total
FROM supply_chain_data
GROUP BY Late_delivery_risk;
-- Resultado inicial: ganancia promedio de $22.40 (a tiempo/risk=0) vs
-- $21.62 (tardía/risk=1) -> diferencia modesta de ~3.5%. La ganancia TOTAL
-- es mayor en tardías solo por efecto de volumen (98,977 vs 81,542 órdenes),
-- no porque sean más rentables individualmente.

-- Profundización: ¿la diferencia se mantiene DENTRO de cada modo de envío,
-- o es un artefacto de qué modos concentran más atrasos?
SELECT "Shipping Mode",
       ROUND(AVG(CASE WHEN Late_delivery_risk = 0 THEN "Order Profit Per Order" END), 2) AS ganancia_prom_a_tiempo,
       ROUND(AVG(CASE WHEN Late_delivery_risk = 1 THEN "Order Profit Per Order" END), 2) AS ganancia_prom_tardia,
       COUNT(*) AS total_ordenes
FROM supply_chain_data
GROUP BY "Shipping Mode";
-- Resultado: en Same Day (22.47 vs 18.92), Second Class (22.58 vs 20.92) y
-- Standard Class (22.42 vs 21.32), la ganancia promedio SÍ es menor en las
-- órdenes tardías, consistente con el hallazgo general.
-- EXCEPCIÓN APARENTE: en First Class, el patrón se invierte (20.39 a
-- tiempo vs 23.26 tardía). Se investigó la causa:
SELECT "Shipping Mode", "Delivery Status", Late_delivery_risk, COUNT(*) AS Count
FROM supply_chain_data
WHERE "Shipping Mode" = 'First Class'
GROUP BY "Shipping Mode", "Delivery Status", Late_delivery_risk;
-- Causa encontrada: First Class NO tiene registros de "Advance shipping" ni
-- "Shipping on time" (consistente con el hallazgo 3.3, donde First Class
-- solo tenía Late delivery y Shipping canceled). Por lo tanto, el grupo
-- "Late_delivery_risk = 0" para First Class está compuesto ÚNICAMENTE por
-- órdenes CANCELADAS (1,301 casos), no por entregas a tiempo. La
-- comparación "a tiempo vs tardía" no es válida para este modo de envío
-- con los datos disponibles -- es una comparación de "canceladas vs
-- tardías", una pregunta distinta. Se documenta como excepción explicada,
-- no como una contradicción real del hallazgo.
-- CONCLUSIÓN FINAL: para los tres modos de envío donde la comparación es
-- válida (Same Day, Second Class, Standard Class), las entregas tardías
-- tienen consistentemente menor rentabilidad promedio que las entregas a
-- tiempo (diferencias de $1.10 a $3.55 por orden). El efecto es real pero
-- modesto (no dramático), y se trata como asociación, no como causalidad
-- comprobada -- no se puede afirmar que el atraso EN SÍ reduzca la
-- ganancia; podría deberse a una tercera variable (ej. tipo de producto o
-- nivel de descuento asociado a cada modo de envío).

-- 3.10 Customer Segment vs. tasa de atraso
SELECT "Customer Segment",
       COUNT(*) AS total_ordenes,
       SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) AS ordenes_tardias,
       ROUND(100.0 * SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_tardias
FROM supply_chain_data
GROUP BY "Customer Segment"
ORDER BY pct_tardias DESC;
-- Hallazgo: Home Office 55.07%, Consumer 54.81%, Corporate 54.72% -- rango
-- de apenas 0.35 puntos porcentuales entre segmentos, el corte más uniforme
-- de todos los analizados hasta ahora. Cuarto corte distinto (junto con
-- Market, Order Region y Category Name) que confirma que el atraso NO se
-- concentra en ningún segmento de cliente -- refuerza la conclusión de que
-- el problema es sistémico y transversal a toda la operación.

-- 3.11 Order Status (SUSPECTED_FRAUD, ON_HOLD, etc.) vs. atraso
SELECT "Order Status",
       COUNT(*) AS total_ordenes,
       SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) AS ordenes_tardias,
       ROUND(100.0 * SUM(CASE WHEN "Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_tardias
FROM supply_chain_data
GROUP BY "Order Status"
ORDER BY pct_tardias DESC;
-- Hallazgo: la mayoría de los estados (PENDING, PENDING_PAYMENT, COMPLETE,
-- PAYMENT_REVIEW, PROCESSING, CLOSED, ON_HOLD) se agrupan en un rango
-- razonablemente uniforme (55.59%-57.9%), algo por encima del promedio
-- general (54.8%). SUSPECTED_FRAUD es la excepción marcada: 0.0% de atraso
-- (0 de 4,062 órdenes). Se investigó la causa:
SELECT "Order Status", "Delivery Status", COUNT(*) AS Count
FROM supply_chain_data
WHERE "Order Status" = 'SUSPECTED_FRAUD'
GROUP BY "Order Status", "Delivery Status";
-- Causa confirmada: el 100% de las órdenes SUSPECTED_FRAUD (4,062 de 4,062)
-- tienen Delivery Status = "Shipping canceled". Tiene sentido de negocio:
-- una orden marcada como fraude sospechoso se cancela antes de entrar al
-- proceso de envío, por lo que nunca puede registrar un atraso -- la
-- operación de envío no llega a ejecutarse para esos casos. No es una
-- anomalía de calidad de dato, es un patrón esperado dada la naturaleza
-- del estado.

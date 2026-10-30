# Propuesta de Proyecto para el TP4 Integrador — GOYS (UTN FR La Plata)

> Propuesta del grupo para el Trabajo Práctico Integrador (TP4). Describe la arquitectura del laboratorio, el stack tecnológico, la cobertura de las tres áreas de la materia y el plan de implementación.
> Este documento refleja fielmente la implementación presente en `demo/`, no una idea preliminar.

---

## 📋 Resumen y Criterios de Selección

| # | Propuesta | Stack Principal | Complejidad | Consumo RAM |
|---|---|---|:---:|:---:|
| **1** | **Mesh VPN Multi-Tenant con Headscale & FRR** | Docker Compose + FRRouting + Headscale + WireGuard/Tailscale | Media | ~2 GB |

> Se evaluaron otras alternativas (EVPN-VXLAN con OSPF, mTLS con Linkerd/K3s). Se eligió esta porque entrega las tres áreas de la materia con un único `docker compose up` y sin dependencia de Internet, que es el requisito de la estación de la Feria de Redes.

---

## 🌐 Propuesta: Hybrid Multi-Tenant Overlay: Mesh VPN con Tailscale/Headscale & FRR

### 1. Concepto y Objetivos

Simular la interconexión de sucursales o centros de cómputo mediante una red subyacente (*underlay*) ruteada dinámicamente con BGP sobre FRRouting, sobre la cual se monta una red privada virtual superpuesta (*overlay mesh*) cifrada con WireGuard y administrada de forma centralizada con **Headscale** (controlador open-source de Tailscale).

**Objetivos del laboratorio:**

- Levantar un *underlay* L3 con **3 routers FRRouting en 3 AS independientes** (65001, 65002, 65000) sobre redes Docker.
- Implementar un **failover real**: enlace directo `router-a ↔ router-b` como camino primario y camino de respaldo vía `router-c`.
- Desplegar el **plano de control Headscale** como servidor de control de la VPN mesh, con DERP embebido para operar sin Internet.
- Conectar clientes finales (agentes Tailscale) de **dos sucursales** con usuarios y grupos separados.
- Asignar los tenants **cruzados entre sucursales** (cada tenant con un nodo en cada sucursal), para que el aislamiento multi-tenant se demuestre por ACL y no por topología.
- Demostrar **aislamiento multi-tenant** mediante ACLs de Headscale.
- Validar que el overlay **mantiene la conectividad** aunque caiga el enlace primario del underlay.
- Mantener la demo **reproducible y sin dependencia de Internet** (redes Docker con NAT/masquerade desactivado: `enable_ip_masquerade: "false"`).

---

### 2. Topología

```
===================================================================================================
                                  CAPA OVERLAY (WireGuard Mesh)
    [host-a1] <====== Túnel Cifrado WireGuard (100.64.0.0/10) ======> [servidor-web]
  (Tenant-A, sucursal A)                                        (Tenant-A, sucursal B)
       |                                                                     |
       X ---- (BLOQUEADO POR ACL) ----> [host-a2] (Tenant-B, misma sucursal A) |
       |                                                                     |
=======|=====================================================================|=====================
       |                              CAPA UNDERLAY (Red L3)                 |
       v                                                                     v
+------------------+                                                +------------------+
|     host-a1      |                                                |     host-a2      |
|   10.10.1.10     |                                                |    10.10.1.11    |
+--------+---------+                                                +--------+---------+
         | (GW: 10.10.1.254)                                                | (GW: 10.10.1.254)
         +----------------------------------+-------------------------------+
                                            |
                                            v
+--------------------------------------------------------------------------------------------------+
|                                  router-a (AS 65001) - 10.10.1.254                               |
+-------------------------------------------+------------------------------------------------------+
         | .1 (net-ab: 10.100.1.0/24)       | .1 (net-transit: 10.100.0.0/24)
         v                                  v
+------------------+              +-------------------+              +-------------------+
|     router-b     |              |     router-c      |              |     headscale     |
|   (AS 65002)     |              |    (AS 65000)     |              |    + hs-routes    |
|   10.20.2.254    |              | (AS de Tránsito)  |              | (Plano de Control)|
+--------+---------+              +-------------------+              +---------+---------+
         | (GW: 10.20.2.254)                                                  | 10.100.0.10
         v                                                                    |
+-------------------------------------------+                                 |
| net-cloud (10.20.2.0/24)                  |<--------------------------------+
|  - servidor-web (10.20.2.10, Tenant-A)    | (Rutas inyectadas por el sidecar hs-routes)
|  - servidor-db  (10.20.2.11, Tenant-B)    |
+-------------------------------------------+
===================================================================================================
```

#### 2.1 Nodos del laboratorio

| Nodo | Rol | IP principal | AS BGP | Redes Docker | Tenant |
|---|---|---|---|---|---|
| `router-a` | Gateway sucursal A | `10.10.1.254` | 65001 | `net-sucursal-a`, `net-transit`, `net-ab` | — |
| `router-b` | Gateway sucursal B / cloud | `10.20.2.254` | 65002 | `net-cloud`, `net-transit`, `net-ab` | — |
| `router-c` | Core / reserva del underlay | `10.100.0.3` | 65000 | `net-transit` | — |
| `headscale` | Plano de control VPN | `10.100.0.10` | — | `net-transit` | — |
| `hs-routes` | Sidecar de rutas estáticas | (comparte netns) | — | `netns: headscale` | — |
| `host-a1` | Cliente Tailscale | `10.10.1.10` | — | `net-sucursal-a` | `tenant-a` |
| `host-a2` | Cliente Tailscale | `10.10.1.11` | — | `net-sucursal-a` | `tenant-b` |
| `servidor-web` | Cliente Tailscale | `10.20.2.10` | — | `net-cloud` | `tenant-a` |
| `servidor-db` | Cliente Tailscale | `10.20.2.11` | — | `net-cloud` | `tenant-b` |

> **Asignación cruzada a propósito:** `host-a2` y `servidor-web` quedaron con el tenant opuesto al de su sucursal. Así `host-a1` (A, tenant-a) y `servidor-web` (B, tenant-a) están en el mismo tenant pero en subredes distintas — cruzan `net-ab`/`net-transit` y prueban el overlay + failover — mientras que `host-a1` y `host-a2` comparten subred pero tenants distintos y quedan bloqueados por ACL, probando que el aislamiento lo da la política y no la red.

#### 2.2 Redes definidas en `demo/docker-compose.yml`

| Red | Subnet | Gateway Docker | Aislamiento | Propósito |
|---|---|---|---|---|
| `net-sucursal-a` | `10.10.1.0/24` | (automático) | sin NAT (masquerade off) | Sucursal A: `host-a1`, `host-a2` |
| `net-cloud` | `10.20.2.0/24` | (automático) | sin NAT (masquerade off) | Sucursal B / cloud: `servidor-web`, `servidor-db` |
| `net-transit` | `10.100.0.0/24` | `10.100.0.254` | sin NAT (masquerade off) | Tránsito: `router-a .1`, `router-b .2`, `router-c .3`, `headscale .10` |
| `net-ab` | `10.100.1.0/24` | `10.100.1.254` | sin NAT (masquerade off) | Enlace directo **primario** `router-a ↔ router-b` |

> **Nota de diseño:** en `net-transit` y `net-ab` el gateway se fijó fuera de `.1` porque Docker asigna `.1` al gateway por defecto y `router-a`/`router-b` usan esa dirección en la red; de lo contrario el contenedor de routing pierde la ruta por defecto.
> **Segmentación offline.** Las cuatro redes se declaran con `driver_opts: {com.docker.network.bridge.enable_ip_masquerade: "false"}`, que desactiva el NAT/masquerade de Docker: no hay traducción de direcciones ni salida a Internet desde las redes del laboratorio. Se optó por este mecanismo **en lugar de `internal: true`** porque las cadenas de iptables de Docker bloqueaban el **ruteo inter-bridge L3** entre redes del underlay (tráfico `router-a → net-ab → router-b`), indispensable para el failover BGP.

#### 2.3 Enlaces del underlay (L3)

| Enlace | Red | Par de IPs | Sesión BGP | Tipo |
|---|---|---|---|---|
| `router-a ↔ router-b` | `net-ab` | `10.100.1.1` ↔ `10.100.1.2` | 65001 ↔ 65002 | **Primario** |
| `router-a ↔ router-c` | `net-transit` | `10.100.0.1` ↔ `10.100.0.3` | 65001 ↔ 65000 | Respaldo |
| `router-b ↔ router-c` | `net-transit` | `10.100.0.2` ↔ `10.100.0.3` | 65002 ↔ 65000 | Respaldo |

#### 2.4 Sesiones BGP y prefijos anunciados

| Router | AS | Vecinos BGP | Prefijos anunciados |
|---|---|---|---|
| `router-a` | 65001 | `10.100.1.2` (B), `10.100.0.3` (C) | `10.10.1.0/24` |
| `router-b` | 65002 | `10.100.1.1` (A), `10.100.0.3` (C) | `10.20.2.0/24` |
| `router-c` | 65000 | `10.100.0.1` (A), `10.100.0.2` (B) | *(ninguno: es un AS de tránsito)* |

Configuración común a los tres routers (`demo/frr/router-{a,b,c}/frr.conf`):

- `no bgp ebgp-requires-policy`: permite las sesiones eBGP sin declarar *route-maps*, simplificando la demo.
- `timers 3 9`: keepalive 3 s / holdtime 9 s, para que el **failover se detecte en pocos segundos** y no en el default de 180 s.
- `log stdout`: los logs de FRR quedan en `docker logs`, útiles para la defensa en la Feria.

#### 2.5 Acceso de los clientes al underlay

| Cliente | Gateway por defecto | Router |
|---|---|---|
| `host-a1`, `host-a2` | `10.10.1.254` | `router-a` |
| `servidor-web`, `servidor-db` | `10.20.2.254` | `router-b` |

El gateway por defecto se fija en el `entrypoint` de cada host (`ip route replace default via ... && exec tailscaled`), de modo que todo el tráfico del agente Tailscale hacia el plano de control sale por el router de su sucursal.

#### 2.6 Plano de control (Headscale)

| Parámetro | Valor |
|---|---|
| URL del servidor | `http://10.100.0.10:8080` |
| API HTTP | `0.0.0.0:8080` |
| API gRPC | `0.0.0.0:50443` (`grpc_allow_insecure: true`) |
| Métricas | `0.0.0.0:9090` |
| Prefijo de la mesh | `100.64.0.0/10` (rango CGNAT de Tailscale), asignación secuencial |
| DERP | Embebido, `region_id: 999`, `region_code: "lab"`, en `10.100.0.10:3478` |
| Base de datos | SQLite (`/etc/headscale/db.sqlite`) |
| MagicDNS | Desactivado (`base_domain: example.com`) |
| Nodos efímeros | `inactivity_timeout: 30m` |
| Política de acceso | `policy.mode: file` → `/etc/headscale/acl.hujson` |

El **DERP embebido** (`automatically_add_embedded_derp_region: true`) es lo que permite que los nodos se coordinen entre sucursales sin depender de los DERP públicos de Tailscale, que no serían alcanzables en un laboratorio sin Internet.

**Sidecar `hs-routes`:** la imagen de Headscale no incluye una shell, por lo que no se pueden agregar rutas dentro de su *network namespace* desde el propio contenedor. La solución es un segundo contenedor (`tailscale/tailscale:latest`) con `network_mode: "service:headscale"` que comparte el namespace de red y ejecuta:

```
ip route replace 10.10.1.0/24 via 10.100.0.1   # hacia router-a
ip route replace 10.20.2.0/24 via 10.100.0.2   # hacia router-b
```

Sin esas rutas, Headscale no alcanzaría las redes de las sucursales y los agentes no podrían completar el *handshake* con el plano de control.

#### 2.7 Aislamiento multi-tenant (ACLs)

La política se define en `demo/headscale/acl.hujson` y define dos grupos de usuarios:

| Grupo | Miembros | Regla |
|---|---|---|
| `group:tenant-a` | `tenant-a@` | `accept` src `group:tenant-a` → dst `group:tenant-a:*` |
| `group:tenant-b` | `tenant-b@` | `accept` src `group:tenant-b` → dst `group:tenant-b:*` |

No existe ninguna regla `accept` entre grupos, por lo que **el tráfico entre `tenant-a` y `tenant-b` se deniega por ausencia de permisos** (deny implícito en Headscale). La segmentación no depende de la topología: es una política centralizada de control de acceso, que es el aporte del área de Seguridad.

`host-a2` y `servidor-web` se registraron a propósito con el tenant opuesto al de su sucursal (ver nota en §2.1), de modo que la prueba de aislamiento (`host-a1` ↔ `host-a2`, misma subred) y la prueba de failover (`host-a1` ↔ `servidor-web`, cruza sucursales) queden desacopladas de la topología física. `tailscale ping` confirma el bloqueo con `no matching peer`: Headscale ni siquiera anuncia el peer entre tenants distintos, no es un paquete descartado en el camino.

#### 2.8 Resumen gráfico del underlay

```
   +-------------------- net-ab . 10.100.1.0/24 --------------------+
   |                                                                 |
   |   router-a (.1)  AS 65001            router-b (.2)  AS 65002     |
   |   [10.10.1.254] <-- BGP directo -->  [10.20.2.254]             |
   +-----------+-------------------------------------+---------------+
               |  net-transit . 10.100.0.0/24        |
               |  +-------- router-c (.3) AS 65000 ----+  |
               |  |      (AS de transito / reserva)     |  |
               |  +---------------+-------------------+  |
               |                  |                      |
        host-a1 (.10) tenant-a    headscale (.10)    servidor-web (.10) tenant-a
        host-a2 (.11) tenant-b    + hs-routes        servidor-db  (.11) tenant-b
                                  (plano de control)
```

Caminos de `host-a1` (sucursal A) hacia `servidor-web` (sucursal B):

| Escenario | Camino | Longitud |
|---|---|---|
| Normal | `host-a1` → `router-a` → **net-ab** → `router-b` → `servidor-web` | 2 saltos de router |
| Caída de `net-ab` | `host-a1` → `router-a` → `router-c` → `router-b` → `servidor-web` | 3 saltos de router (failover BGP) |

#### 2.9 Monitoreo y observabilidad (Prometheus + Grafana)

| Componente | IP (`net-transit`) | Acceso desde el host | Función |
|---|---|---|---|
| `frr-exporter-a/b/c` | `10.100.0.31` / `.32` / `.33` (`:9342`) | — | `frr_exporter` por router; lee los sockets de FRR por un volumen compartido (`frr-run-{a,b,c}`) y expone métricas BGP |
| `prometheus` | `10.100.0.20` | `http://localhost:9091` | Scraping cada 5 s de los 3 exporters FRR y de Headscale (`10.100.0.10:9090`); reglas de alerta |
| `grafana` | `10.100.0.21` | `http://localhost:3000` (`admin`/`admin`) | Datasource y dashboard **Lab Mesh VPN** provisionados automáticamente |

Archivos: `demo/prometheus/prometheus.yml`, `demo/prometheus/alerts.yml`, `demo/grafana/provisioning/` y `demo/grafana/dashboards/lab-mesh.json`.

- **Dashboard:** estado de las sesiones BGP (actual y en el tiempo, para ver el failover), prefijos recibidos, uptime, tasa de mensajes BGP, estado de los targets y goroutines de Headscale.
- **Alertas:** `BGPPeerCaido` (`frr_bgp_peer_state == 0` por 5 s) y `ExporterCaido` (`up == 0` por 15 s).
- **Validado:** al cortar `net-ab`, las sesiones directas `router-a ↔ router-b` pasan a 0 en Prometheus, `BGPPeerCaido` pasa a `firing`, `router-a` reconverge por `net-transit` y al restaurar el enlace las 6 sesiones vuelven a 1.
- El monitoreo vive en `net-transit` y no modifica la topología del underlay.

---

### 3. Cobertura de las 3 Áreas de la Materia

| Área | Qué cubre en este TP | Estado |
|---|---|---|
| 🔌 **Redes** | Topología L3 underlay con BGP entre 3 AS, failover de enlaces, redes Docker segmentadas (L3, sin NAT), containerizacion de routers | **Implementado** |
| ⚙️ **Operación (Gestión)** | Despliegue reproducible con Docker Compose, aprovisionamiento de agentes Tailscale, inyeccion de rutas en el plano de control, logs de FRR centralizados | **Implementado** (monitoreo con Prometheus + Grafana, ver §2.9) |
| 🛡️ **Seguridad** | Control de acceso centralizado (ACLs de Headscale), aislamiento estricto entre `tenant-a` y `tenant-b`, cifrado WireGuard punto a punto | **Implementado** |

**Alcance real vs. alcance máximo de la materia.** El TP4 pide integrar las tres áreas, no implementarlas todas por completo. Lo que hoy esta implementado cobre Redes, Seguridad y la base de Operación. El monitoreo con Prometheus + Grafana ya está implementado (§2.9); los ítems que siguen pendientes están en §6.

---

### 4. Paso a Paso de Implementación

1. **Levantar el underlay L3** con Docker Compose: 3 routers FRRouting (`router-a`, `router-b`, `router-c`) en las redes `net-sucursal-a`, `net-cloud`, `net-transit` y `net-ab`, con BGP entre ellos.

   ```bash
   cd demo
   docker compose up -d
   ```

2. **Desplegar el plano de control Headscale** en `net-transit` (`10.100.0.10`), con DERP embebido, más el sidecar `hs-routes` que inyecta las rutas estáticas hacia ambas sucursales.

3. **Conectar los agentes Tailscale** en cada cliente (`host-a1`, `host-a2`, `servidor-web`, `servidor-db`) apuntando a Headscale (`--login-server http://10.100.0.10:8080`) y autenticarlos.

4. **Crear los tenants** en Headscale (`tenant-a`, `tenant-b`) y registrar los usuarios correspondientes; el `acl.hujson` define los grupos y aísla el tráfico entre sucursales.

5. **Verificar el estado de BGP** en cada router y confirmar que `router-a` y `router-b` se alcanzan por el camino primario (`net-ab`).

6. **Simular la caida del enlace primario** y comprobar el failover:

   ```bash
   # cortar net-ab entre router-a y router-b
   docker network disconnect -f net-ab router-a
   # observar la caida de la sesion BGP y el desvio por router-c
   docker exec router-a vtysh -c "show bgp summary"
   # restaurar
   docker network connect --ip 10.100.1.1 net-ab router-a
   ```

7. **Validar el aislamiento multi-tenant**: comprobar que `host-a1` alcanza a `servidor-web` (mismo tenant, cruza sucursales) y que no alcanza a `host-a2` (misma subred, tenant distinto) por la ACL, y que el overlay sigue operativo tras el failover.

---

### 5. Stack Tecnológico

| Capa | Tecnología | Versión / Detalle | Rol en el TP |
|---|---|---|---|
| Orquestación | Docker Compose | `docker-compose.yml` en `demo/` | Levanta y conecta toda la topología |
| Ruteo | FRRouting (FRR) | Imagen con `vtysh` | 3 routers BGP (`router-a/b/c`) |
| Protocolo de ruta | BGP eBGP | AS 65001 / 65002 / 65000 | Ruteo dinámico y failover |
| Overlay VPN | Tailscale (agente) | `tailscale/tailscale` | Cifrado WireGuard en los clientes |
| Plano de control | Headscale | Controlador open-source | Registro, tenants, ACLs, DERP embebido |
| Base de control | SQLite | `/etc/headscale/db.sqlite` | Estado de nodos y usuarios |
| Configuración | Hujson / YAML | `acl.hujson`, `config.yaml` | Política de acceso y config. del control plane |
| Red | Redes Docker bridging sin NAT | 4 redes con `enable_ip_masquerade: "false"` | Underlay L3 segmentado, sin masquerade ni salida a Internet |

---

### 6. Trabajo Futuro (Pendiente)

Estos ítems **no están implementados** en el laboratorio actual; se documentan para cerrar el alcance del TP y para las etapas siguientes:

| # | Ítem | Área | Descripción |
|---|---|---|---|
| 1 | **Aprovisionamiento con Ansible** | Operación | Playbooks para crear tenants, registrar usuarios, entregar las *auth keys* a los agentes y aplicar la `acl.hujson` de forma declarativa e idempotente, en lugar de los pasos manuales de Headscale CLI. |
| 3 | **OSPF como alternativa a BGP** | Redes | Agregar OSPF como segundo protocolo de ruta para comparar convergence times y comportamiento de failover frente a eBGP. |
| 4 | **Pruebas automatizadas de aceptación** | Operación / Redes | Script que valide el failover (caída y restauración de `net-ab`) y el aislamiento multi-tenant de forma automática en cada entrega. |
| 5 | **Documento final y póster A1** | General | Documento PDF con la memoria del TP y póster tamaño A1 para la presentación de la Feria de Redes. |

---

### 7. Cómo Levantar y Verificar el Laboratorio

```bash
cd demo
docker compose up -d          # levanta underlay + headscale + agentes

# Estado de BGP en cada router
docker exec router-a vtysh -c "show bgp summary"
docker exec router-b vtysh -c "show bgp summary"
docker exec router-c vtysh -c "show bgp summary"

# Estado de los nodos en el plano de control
docker exec headscale headscale nodes list

# Conectividad intra-tenant (debe responder, cruza sucursales por net-ab/net-transit)
docker exec host-a1 ping -c2 servidor-web

# Aislamiento inter-tenant (debe fallar por ACL, misma subred)
docker exec host-a1 ping -c2 host-a2
```

**Prueba de failover sugerida:** desconectar `net-ab` de `router-a` y observar en `show bgp summary` cómo la sesión con `router-b` cae y el tráfico se desvía por `router-c`, manteniéndose la conectividad del overlay.

---

## 📌 Notas Finales

- El laboratorio **no depende de Internet**: el DERP de Headscale es embebido y no se descarga nada en tiempo de demo. La separación de las redes se logra desactivando el NAT/masquerade de Docker (`enable_ip_masquerade: "false"`), no con `internal: true`.
- El **failover es real**, no simulado: depende de las sesiones eBGP entre los tres AS con timers cortos (`timers 3 9`).
- La **segmentación multi-tenant** no depende de la topología física sino de la política centralizada en `acl.hujson`.
- El sidecar `hs-routes` es una pieza obligatoria del diseño: sin él, Headscale no tiene rutas hacia las sucursales y los agentes no pueden registrarse.
- Los ítems de §6 (Ansible, OSPF, pruebas automatizadas, PDF/póster) quedan pendientes y **no deben presentarse como implementados**.

---

INCONSISTENCIA EN CAPTURAS <--- REVISARLAS

Me parece bien, y no es innecesario — resuelve un problema real del diseño actual: con tenant-a = sucursal A y tenant-b = sucursal B, el aislamiento inter-tenant y el cruce de sucursales (failover) nunca se prueban juntos, porque el único tráfico permitido por ACL ya era intra-sucursal. Tu reasignación hace que:

- `host-a1 ↔ servidor-web` (mismo tenant, cruza `net-ab`) valide overlay + failover real.
- `host-a1 ↔ host-a2` (misma subred, distinto tenant) valide que el aislamiento es por ACL y no por topología.

Es justo el tipo de prueba que un jurado va a pedir ("¿cómo sabés que no es la red la que aísla?"), así que vale la pena.

Dos detalles a confirmar, no a descartar:

1. **Sintaxis del CLI**: en headscale v0.29.5 el subcomando es `nodes move` con `-i/--identifier` (ID numérico del nodo) y `-u/--user` — pero convendría correr `docker exec headscale headscale nodes move --help` antes de tirar los comandos a ciegas, porque en algunas versiones `-u` espera el **nombre** del user, no el ID (al revés que `preauthkeys create`, que sí pedía ID numérico). Vale la pena no asumir.
2. **Consistencia con la documentación**: `propuesta-tp4.md` tiene la tabla de nodos (§2.1), el diagrama ASCII y la tabla de ACLs (§2.7) escritos con la asignación vieja (host-a1/host-a2 = tenant-a, servidor-web/servidor-db = tenant-b). Si aplicás el cambio, esos tres lugares quedan desactualizados y hay que tocarlos para que el documento siga reflejando "la implementación presente en demo/", como dice el propio encabezado.

Sobre tu nota de `no matching peer`: correcto, es el comportamiento esperado y deseable de Headscale (ACL se aplica en el *map response*, ni siquiera anuncia el peer) — es mejor evidencia de aislamiento que un ping bloqueado a nivel de paquete.

```

✅ **Paso 1-3 completamente funcionales**: BGP Established (primario `net-ab` + backup vía `router-c`), Headscale estable, 4 agentes unidos al mesh.
✅ **Reasignación de tenants aplicada**: `host-a2`→tenant-b (`100.64.0.5`), `servidor-web`→tenant-a (`100.64.0.6`), vía logout + delete + rejoin (no existe `nodes move` en esta versión de headscale, solo `delete`/`rename`/`tag`).
✅ **Aislamiento por ACL confirmado**: `host-a1↔host-a2` da `no matching peer` (bloqueo a nivel de control plane, no de paquete).
✅ **Cruce de sucursal confirmado**: `host-a1↔servidor-web` responde con ruta directa.
✅ **Failover real probado**: se cortó `net-ab`, la sesión BGP primaria cayó a `Active`, la ruta a `10.20.2.0/24` reconvergió vía `router-c`, el overlay perdió solo 1 paquete, y se restauró el enlace primario sin problemas.

`propuesta-tp4.md` quedó actualizado (tabla de nodos §2.1, diagramas §2 y §2.8, ACL §2.7, pasos §4 y §7) para reflejar la asignación cruzada real.

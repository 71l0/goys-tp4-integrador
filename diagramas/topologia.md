# Diagrama de Topología — TP4 GOYS

> Arquitectura del laboratorio: Mesh VPN Multi-Tenant con Headscale & FRRouting.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#007acc', 'edgeLabelBackground':'#fff', 'fontFamily': 'Arial'}}}%%

graph TB
    subgraph UNDERLAY["UNDERLAY L3 — eBGP (FRRouting)"]
        direction TB
        ra["router-a<br/>AS 65001<br/>10.100.0.1"]
        rb["router-b<br/>AS 65002<br/>10.100.0.2"]
        rc["router-c<br/>AS 65000<br/>10.100.0.3"]
    end

    subgraph SUCURSAL_A["net-sucursal-a — 10.10.1.0/24"]
        ha1["host-a1<br/>10.10.1.10<br/>Tenant-A"]
        ha2["host-a2<br/>10.10.1.11<br/>Tenant-B"]
        ra_gw["router-a<br/>10.10.1.254"]
    end

    subgraph SUCURSAL_B["net-cloud — 10.20.2.0/24"]
        sw["servidor-web<br/>10.20.2.10<br/>Tenant-A"]
        sd["servidor-db<br/>10.20.2.11<br/>Tenant-B"]
        rb_gw["router-b<br/>10.20.2.254"]
    end

    subgraph TRANSIT["net-transit — 10.100.0.0/24"]
        rc
        hs["headscale<br/>10.100.0.10<br/>DERP embebido"]
        hsr["hs-routes<br/>sidecar"]
    end

    subgraph MON["Monitoreo — Prometheus + Grafana"]
        prom["prometheus<br/>10.100.0.20:9090"]
        grafana["grafana<br/>10.100.0.21:3000"]
        ex_a["frr-exporter-a<br/>10.100.0.31"]
        ex_b["frr-exporter-b<br/>10.100.0.32"]
        ex_c["frr-exporter-c<br/>10.100.0.33"]
    end

    %% Underlay BGP
    ra ---|"eBGP 65001 &harr; 65002 (primario)"| rb
    ra ---|"eBGP 65001 &harr; 65000 (backup)"| rc
    rb ---|"eBGP 65002 &harr; 65000"| rc

    %% Conexión a sucursales
    ra_gw --- ha1
    ra_gw --- ha2
    rb_gw --- sw
    rb_gw --- sd

    %% Overlay WireGuard (Headscale)
    ha1 -.->|"WireGuard tunnel"| hs
    ha2 -.->|"WireGuard tunnel"| hs
    sw -.->|"WireGuard tunnel"| hs
    sd -.->|"WireGuard tunnel"| hs

    %% Headscale sidecar de rutas
    hs --- hsr

    %% Monitoreo
    ex_a -.->|"frr_bgp_peer_*"| prom
    ex_b -.->|"frr_bgp_peer_*"| prom
    ex_c -.->|"frr_bgp_peer_*"| prom
    hs -.->|"go_*"| prom
    prom -.->|"datasource"| grafana

    %% Enlaces lógicos de failover
    ra -.->|"ruta primaria: net-ab"| rb
    ra -.->|"ruta backup: net-transit"| rc
    rb -.->|"ruta backup: net-transit"| rc

    classDef router fill:#e1f5e1,stroke:#333,stroke-width:2px;
    classDef host fill:#e3f2fd,stroke:#333,stroke-width:1px;
    classDef svc fill:#fff3e0,stroke:#333,stroke-width:2px;
    classDef mon fill:#f3e5f5,stroke:#333,stroke-width:2px;

    class ra,rb,rc router;
    class ha1,ha2,sw,sd host;
    class hs,hsr svc;
    class prom,grafana,ex_a,ex_b,ex_c mon;
```

## Descripción de segmentos

| Red | CIDR | Propósito |
|-----|------|-----------|
| net-sucursal-a | 10.10.1.0/24 | Sucursal A (host-a1, host-a2, gateway router-a) |
| net-cloud | 10.20.2.0/24 | Sucursal B (servidor-web, servidor-db, gateway router-b) |
| net-transit | 10.100.0.0/24 | Tránsito underlay entre routers y servicios centrales |
| net-ab | 10.100.1.0/24 | Enlace directo primario router-a ↔ router-b |

## Flujo de tráfico clave

1. **Underlay BGP:** router-a y router-b forman sesión eBGP directa por `net-ab` (camino primario). Ambas forman sesión con router-c por `net-transit` (camino de respaldo). Fallback real ante caída de `net-ab`.
2. **Overlay WireGuard:** los 4 nodos finales se registran en Headscale y crean túneles cifrados entre sí. El aislamiento multi-tenant se aplica por ACL en `acl.hujson` (intra-tenant permitido, inter-tenant denegado).
3. **Monitoreo:** `frr_exporter` expone métricas BGP de cada router; Prometheus las scrapea cada 5s; Grafana las visualiza en el dashboard `lab-mesh`.
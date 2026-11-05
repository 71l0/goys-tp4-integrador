# Bitácora del grupo — TP4

> Registrar acá el avance: qué hizo cada integrante, decisiones tomadas y pendientes.
> Esto ayuda a coordinar el trabajo y deja evidencia de la participación de todos.

---

## 👥 Integrantes

| Nombre | Usuario de GitHub | Rol en el grupo |
|--------|-------------------|-----------------|
| Ulises Bucchino | ulisesutnfrlp7 | Infraestructura de red, FRR, underlay BGP, failover |
| Sofía Raggi | 71l0 | Automatización con Ansible (4 playbooks) |
| Jano Stratakis | jano.stra | Monitoreo Prometheus + Grafana, dashboards, alertas |
| Valentín Garzaniti | valenxity | Refactorización y mejoras |
|        |                   |                 |

## 🎯 Proyecto

- **Modalidad:** A — Desarrollo
- **Tema:** Mesh VPN Multi-Tenant con Headscale y FRRouting
- **Problema/objetivo:** Interconectar sucursales con underlay L3 ruteado por BGP (failover real por caída de enlace) y overlay WireGuard con aislamiento multi-tenant por ACL de Headscale.

## 🗓️ Registro de avance

| Fecha | Qué se hizo | Quién | Commit |
|-------|-------------|-------|--------|
| 2026-10-21 | Configura underlay L3 con BGP y despliega overlay con Headscale (3 routers FRR, 4 nodos overlay) | Ulises Bucchino | feat(demo): configura underlay L3 con BGP y despliega overlay con Headscale. |
| 2026-10-26 | Merge PR de underlay/overlay | Sofia.Raggi | Merge pull request #1 from 71l0/configuraUnderlayL3YDespliegaPlanoDeControlOverlay |
| 2026-10-27 | Automatización y Gestión Operativa (Ansible) | Sofia.Raggi | feat(ansible): Automatización y Gestión Operativa |
| 2026-10-29 | Automatización y Gestión Operativa (Ansible) | Ulises Mateo Bucchino | feat(ansible): automatización y gestión operativa. |
| 2026-10-29 | Actualiza propuesta-tp4.md con topología y nodos | Sofia.Raggi | Update propuesta-tp4.md with topology and nodes |
| 2026-10-29 | Prometheus + Grafana con frr_exporter y alertas BGP | Jano Stratakis | feat(monitoreo): Prometheus + Grafana con frr_exporter y alertas BGP |
| 2026-10-29 | Evidencia de monitoreo con Prometheus y Grafana (capturas) | Jano Stratakis | docs(capturas): evidencia de monitoreo con Prometheus y Grafana |
| 2026-11-02 | Reacomoda IPs de nodos para ejecutar correctamente el playbook 4 de Ansible | Ulises Bucchino | refactor(ansible): reacomoda IPs de nodos para ejecutar correctamente el playbook 4 de Ansible. |
| 2026-11-02 | Reacomoda IPs de nodos para ejecutar correctamente el playbook 4 de Ansible | Ulises Mateo Bucchino | refactor(ansible): reacomoda IPs de nodos para ejecutar correctamente el playbook 4 de Ansible. |
| 2026-11-02 | Implementa monitoreo con Prometheus y Grafana | Ulises Mateo Bucchino | feat(ops): implementa monitoreo con Prometheus y Grafana. |
| 2026-11-03 | Playbook para respaldo versionado de configuraciones de FRR | Valentín Garzaniti | feat(ansible): agrega playbook para respaldo versionado de configuraciones de FRR |
| 2026-11-03 | Runbook de procedimientos operativos, failover y recuperación | Valentín Garzaniti | docs(ops): agrega runbook con procedimientos operativos, failover y recuperacion |

## Estado de servicios (demo/)

| Servicio | Estado | Notas |
|----------|--------|-------|
| Underlay FRR (router-a/b/c) | Implementado | 3 AS (65001, 65002, 65000), eBGP, failover por caída de net-ab |
| Overlay Headscale | Implementado | 4 nodos, DERP embebido, ACL intra-tenant |
| Ansible | Implementado | 5 playbooks: preflight, underlay, overlay, conectividad, respaldo |
| Prometheus + Grafana | Implementado | frr_exporter, alertas BGP, dashboard lab-mesh |
| Documentación Operativa | Implementado | Runbook de gestión, failover y contingencia (`documento/runbook.md`) |

## 🚧 Pendientes / decisiones

- [ ] Generar documento final en PDF desde `documento/tp4.md`
- [ ] Agregar póster A1 (editable + PDF) en `poster/`
- [ ] Revisar IPs Tailscale hardcodeadas en `ansible/playbooks/04-pruebas-conectividad.yml` si cambia el orden de join

## 📝 Notas

- Ideas, dudas para el docente, riesgos, etc.

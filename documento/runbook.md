# Runbook de Procedimientos Operativos — Laboratorio Mesh VPN (TP4 GOYS)

**Proyecto:** Mesh VPN Multi-Tenant con Headscale & FRRouting  
**Cátedra:** Gestión Operativa y Seguridad en Redes (UTN FR La Plata)  
**Entorno:** Docker Compose (offline, redes sin masquerade L3)

---

## 1. Puesta en Marcha del Entorno

### 1.1. Verificación previa de requisitos
- Docker Engine 24+ y Docker Compose v2.
- Puertos libres en el host: `9091` (Prometheus) y `3000` (Grafana).
- Memoria RAM disponible: mínimo 2 GB.

### 1.2. Despliegue de los servicios
Desde la raíz del proyecto o desde el directorio `demo/`:

```bash
cd demo
docker compose up -d
```

### 1.3. Validación automática con Ansible
Desde la carpeta `ansible/`:

```bash
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/01-preflight.yml
ansible-playbook -i inventory/hosts.yml playbooks/02-validar-underlay.yml
ansible-playbook -i inventory/hosts.yml playbooks/03-validar-overlay.yml
ansible-playbook -i inventory/hosts.yml playbooks/04-pruebas-conectividad.yml
```

---

## 2. Operación y Gestión del Underlay L3 (BGP)

### 2.1. Inspección de sesiones BGP en routers
Para validar que las sesiones eBGP estén en estado `Established`:

```bash
docker exec router-a vtysh -c "show bgp summary"
docker exec router-b vtysh -c "show bgp summary"
docker exec router-c vtysh -c "show bgp summary"
```

### 2.2. Inspección de tablas de enrutamiento
Confirmar que `router-a` conoce la subred de Sucursal B (`10.20.2.0/24`) y `router-b` la de Sucursal A (`10.10.1.0/24`):

```bash
docker exec router-a vtysh -c "show ip route bgp"
```

### 2.3. Respaldo de configuraciones en caliente
Para resguardar el estado activo de los tres routers de forma automatizada:

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/05-backup-configs.yml
```
Los archivos se guardarán versionados en `backups/frr/router-{a,b,c}-YYYY-MM-DD.cfg`.

---

## 3. Demostración de Resiliencia: Simulación de Failover

El enlace primario directo entre `router-a` y `router-b` ocurre a través de la red Docker `net-ab`.

### 3.1. Provocar la caída del enlace primario
```bash
docker network disconnect -f net-ab router-a
```

### 3.2. Verificación del desvío por camino de respaldo
1. **Verificar BGP en `router-a`:**
   ```bash
   docker exec router-a vtysh -c "show bgp summary"
   ```
   *Resultado esperado:* El vecino `10.100.1.2` pasa a estado `Active` o inactivo; el vecino `10.100.0.3` (`router-c`) permanece `Established`.
2. **Verificar ruta activa en `router-a`:**
   ```bash
   docker exec router-a vtysh -c "show ip route 10.20.2.0/24"
   ```
   *Resultado esperado:* Next-hop conmutado a `10.100.0.3` (`router-c`).
3. **Verificar tráfico del overlay en vivo:**
   ```bash
   docker exec host-a1 tailscale ping servidor-web
   ```
   *Resultado esperado:* El ping se mantiene operativo respondiendo por el camino alternativo.
4. **Verificar alertas en Prometheus / Grafana:**
   - En Prometheus (`http://localhost:9091/alerts`), la alerta `BGPPeerCaido` pasa a estado `FIRING` tras 5 segundos.
   - En Grafana (`http://localhost:3000`), el panel BGP refleja la caída de la sesión directa.

### 3.3. Restauración del enlace primario
```bash
docker network connect --ip 10.100.1.1 net-ab router-a
```
Tras 3 a 5 segundos, la sesión directa eBGP se restablece, el tráfico conmuta nuevamente a la ruta de 2 saltos (`net-ab`) y la alerta en Prometheus se resuelve automáticamente (`resolved`).

---

## 4. Validación de Seguridad y Aislamiento Multi-Tenant

La política de control de acceso se define en `demo/headscale/acl.hujson`.

### 4.1. Conectividad permitida (Intra-tenant)
- `host-a1` hacia `servidor-web` (ambos pertenecen a `tenant-a`, cruzando sucursales):
  ```bash
  docker exec host-a1 tailscale ping servidor-web
  docker exec host-a1 ping -c 3 100.64.0.6
  ```
  *Resultado:* Tráfico cifrado permitido y exitoso.

### 4.2. Aislamiento forzado (Inter-tenant)
- `host-a1` (Tenant-A) hacia `host-a2` (Tenant-B, misma subred `net-sucursal-a`):
  ```bash
  docker exec host-a1 tailscale ping host-a2
  ```
  *Resultado:* Respuesta `no matching peer`. Headscale aplica filtrado a nivel de plano de control y ni siquiera anuncia el peer WireGuard.

---

## 5. Procedimientos de Recuperación y Rollback

### 5.1. Reinicio del plano de control Headscale
Si los clientes pierden sincronización con el controlador o se modificó `acl.hujson`:
```bash
docker compose -f demo/docker-compose.yml restart headscale
```
*Nota:* El sidecar `hs-routes` mantendrá las rutas estáticas en el namespace. Si se recrea el contenedor `headscale`, ejecutar también `docker compose -f demo/docker-compose.yml restart hs-routes`.

### 5.2. Limpieza total y reinicio desde cero
En caso de estado inconsistente en la base de datos o en la red:
```bash
cd demo
docker compose down -v
docker compose up -d
```
Esperar 10 segundos a que los daemons de FRR y los agentes Tailscale inicien y volver a ejecutar la suite de Ansible (`01` a `04`).

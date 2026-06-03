# MongoDB Replica Set de 3 Nodos con Docker Compose

Esta plantilla despliega un Replica Set de MongoDB de 3 nodos con una estructura modular y portable. El mismo codigo sirve para dos escenarios:

1. Desarrollo local en un solo servidor.
2. Produccion o laboratorio distribuido en 3 servidores Linux distintos.

La clave de este enfoque es usar `network_mode: host` y parametrizar hostnames, puertos y nombre del Replica Set desde `.env`. Asi cada contenedor se comporta como un proceso del host y no depende de una red Docker local que dejaria de funcionar al separar los nodos en maquinas distintas.

## Estructura

```text
mongo-cluster/
├── .env
├── deploy.sh
├── README.md
├── node1/
│   └── docker-compose.yml
├── node2/
│   └── docker-compose.yml
└── node3/
    └── docker-compose.yml
```

## Como funciona la arquitectura

Cada nodo:

1. Usa `mongo:6.0.14`.
2. Ejecuta `mongod` con `--replSet`, `--keyFile` y `--bind_ip_all`.
3. Monta el archivo `mongo.key` en modo solo lectura en `/opt/mongo/mongo.key`.
4. Usa almacenamiento persistente local en `./data` dentro de cada carpeta de nodo.

Por que `network_mode: host`:

1. En local, los tres nodos escuchan en puertos distintos del mismo host.
2. En distribuido, cada nodo escucha en el puerto configurado de su propio servidor.
3. El Replica Set siempre se forma usando `hostname:puerto` reales definidos en `.env`.
4. No depende de una red bridge de Docker, que solo existe dentro de una maquina.

## Variables globales

Edita `.env` antes de desplegar:

```dotenv
MONGO_IMAGE=mongo:6.0.14

MONGO_REPLICA_SET_NAME=rs0

MONGO_ROOT_USERNAME=admin
MONGO_ROOT_PASSWORD=change_this_admin_password_now

MONGO_NODE1_HOST=mongo-node1
MONGO_NODE1_ADDRESS=127.0.0.1
MONGO_NODE1_PORT=27117
MONGO_NODE1_NAME=mongo-rs-node1

MONGO_NODE2_HOST=mongo-node2
MONGO_NODE2_ADDRESS=127.0.0.1
MONGO_NODE2_PORT=27118
MONGO_NODE2_NAME=mongo-rs-node2

MONGO_NODE3_HOST=mongo-node3
MONGO_NODE3_ADDRESS=127.0.0.1
MONGO_NODE3_PORT=27119
MONGO_NODE3_NAME=mongo-rs-node3
```

## Despliegue local en un solo servidor

### Requisitos

1. Docker Engine con `docker compose`.
2. `openssl` instalado.
3. Que los hostnames del `.env` resuelvan localmente para clientes externos.

### Configurar `/etc/hosts` en local

Si no tienes DNS local, agrega esto al `/etc/hosts` del servidor donde vas a probar:

```text
127.0.0.1 mongo-node1
127.0.0.1 mongo-node2
127.0.0.1 mongo-node3
```

Esto permite que el Replica Set use hostnames amigables aunque los tres nodos corran en la misma maquina.

Ademas, cada `docker-compose.yml` inyecta esos hostnames dentro del contenedor con `extra_hosts`, asi que la replicacion interna tambien funciona cuando todo vive en el mismo servidor.

### Desplegar

Desde la raiz `mongo-cluster`:

```bash
chmod +x deploy.sh
./deploy.sh
```

El script hace lo siguiente:

1. Valida dependencias.
2. Genera `mongo.key` con `openssl rand -base64 756` si no existe.
3. Copia ese keyfile a `node1`, `node2` y `node3` con permisos `400`.
4. Levanta los tres `docker-compose.yml`.
5. Espera salud de contenedores y respuesta de MongoDB.
6. Ejecuta `rs.initiate()` con los hostnames y puertos definidos en `.env`.
7. Espera a que se elija el `primary`.
8. Crea el usuario administrador en `admin` con rol `root`.

No hace falta tener `mongosh` instalado en el host para este despliegue local. El script usa `mongosh` dentro de los propios contenedores.

## Despliegue en 3 servidores Linux distintos

### Idea general

Usas exactamente el mismo codigo, pero cada servidor levanta solo su nodo:

1. `server-1` levanta `node1`.
2. `server-2` levanta `node2`.
3. `server-3` levanta `node3`.

### Requisitos previos

En los 3 servidores:

1. Docker Engine con `docker compose`.
2. Espacio para persistencia.
3. Conectividad privada entre las tres IPs.
4. El mismo `.env` en los tres servidores.
5. El mismo `mongo.key` en los tres servidores.

### Paso 1: copiar el proyecto

Copia la carpeta `mongo-cluster` completa a cada servidor.

Ejemplo conceptual:

1. `mongo-node1` recibe todo el proyecto.
2. `mongo-node2` recibe todo el proyecto.
3. `mongo-node3` recibe todo el proyecto.

### Paso 2: ajustar `.env`

En los tres servidores, el `.env` debe ser identico y debe apuntar a hostnames o DNS privados reales.

Ejemplo distribuido:

```dotenv
MONGO_NODE1_HOST=mongo-node1
MONGO_NODE1_ADDRESS=10.10.10.11
MONGO_NODE1_PORT=27017

MONGO_NODE2_HOST=mongo-node2
MONGO_NODE2_ADDRESS=10.10.10.12
MONGO_NODE2_PORT=27017

MONGO_NODE3_HOST=mongo-node3
MONGO_NODE3_ADDRESS=10.10.10.13
MONGO_NODE3_PORT=27017
```

En un entorno real distribuido es normal que todos usen `27017`, porque cada uno vive en una maquina distinta.

### Paso 3: configurar resolucion de nombres

Si no tienes DNS interno, configura `/etc/hosts` en las 3 maquinas.

Ejemplo:

```text
10.10.10.11 mongo-node1
10.10.10.12 mongo-node2
10.10.10.13 mongo-node3
```

Debes agregar las tres lineas en las tres maquinas.

Importante: las variables `MONGO_NODE1_ADDRESS`, `MONGO_NODE2_ADDRESS` y `MONGO_NODE3_ADDRESS` deben coincidir con esas IPs privadas para que los contenedores tambien puedan resolver correctamente a los otros nodos.

### Paso 4: distribuir el keyfile

Genera `mongo.key` una sola vez y copialo identico a los tres servidores. Todos los nodos deben compartir el mismo contenido.

Permisos requeridos:

```bash
chmod 400 mongo.key
```

Colocalo en:

1. `node1/mongo.key` en el servidor 1.
2. `node2/mongo.key` en el servidor 2.
3. `node3/mongo.key` en el servidor 3.

### Paso 5: levantar cada nodo

En cada servidor, levanta solo su compose.

`deploy.sh` no se usa en este escenario distribuido.

Servidor 1:

```bash
docker compose --env-file .env -f node1/docker-compose.yml up -d
```

Servidor 2:

```bash
docker compose --env-file .env -f node2/docker-compose.yml up -d
```

Servidor 3:

```bash
docker compose --env-file .env -f node3/docker-compose.yml up -d
```

### Paso 6: iniciar el Replica Set desde el servidor 1

Conecta al nodo 1 por localhost y ejecuta `rs.initiate()` desde la maquina que aloja `node1`.

Ejemplo:

```bash
mongosh --host 127.0.0.1 --port 27017
```

Luego:

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo-node1:27017", priority: 2 },
    { _id: 1, host: "mongo-node2:27017", priority: 1 },
    { _id: 2, host: "mongo-node3:27017", priority: 1 }
  ]
})
```

### Paso 7: crear el usuario administrador

Despues de que el nodo 1 sea `primary`, crea el usuario en `admin` usando la localhost exception desde el servidor 1:

```javascript
db = db.getSiblingDB('admin')
db.createUser({
  user: 'admin',
  pwd: 'change_this_admin_password_now',
  roles: [
    { role: 'root', db: 'admin' }
  ]
})
```

## Firewall recomendado

Nunca expongas MongoDB directamente a internet.

Permite solo trafico entre las IPs privadas de los 3 servidores y desde hosts de administracion confiables.

### Ejemplo con UFW

Servidor 1:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.10.10.12 to any port 27017 proto tcp
ufw allow from 10.10.10.13 to any port 27017 proto tcp
ufw allow from 10.10.20.10 to any port 22 proto tcp
ufw enable
```

Servidor 2:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.10.10.11 to any port 27017 proto tcp
ufw allow from 10.10.10.13 to any port 27017 proto tcp
ufw allow from 10.10.20.10 to any port 22 proto tcp
ufw enable
```

Servidor 3:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.10.10.11 to any port 27017 proto tcp
ufw allow from 10.10.10.12 to any port 27017 proto tcp
ufw allow from 10.10.20.10 to any port 22 proto tcp
ufw enable
```

### Ejemplo conceptual con iptables

```bash
iptables -A INPUT -p tcp -s 10.10.10.11 --dport 27017 -j ACCEPT
iptables -A INPUT -p tcp -s 10.10.10.12 --dport 27017 -j ACCEPT
iptables -A INPUT -p tcp -s 10.10.10.13 --dport 27017 -j ACCEPT
iptables -A INPUT -p tcp --dport 27017 -j DROP
```

Adapta las IPs a tu red privada real.

## Connection strings

### Local en un solo host

```text
mongodb://admin:change_this_admin_password_now@mongo-node1:27117,mongo-node2:27118,mongo-node3:27119/admin?replicaSet=rs0
```

### Distribuido en 3 hosts

```text
mongodb://admin:change_this_admin_password_now@mongo-node1:27017,mongo-node2:27017,mongo-node3:27017/admin?replicaSet=rs0
```

El parametro `?replicaSet=rs0` le indica al driver que debe descubrir el estado del Replica Set y reconectar automaticamente al `primary` correcto o a otro miembro disponible segun la operacion.

## Verificaciones utiles

Estado del Replica Set:

```bash
mongosh "mongodb://admin:change_this_admin_password_now@mongo-node1:27117,mongo-node2:27118,mongo-node3:27119/admin?replicaSet=rs0"
```

Dentro de `mongosh`:

```javascript
rs.status()
db.adminCommand({ ping: 1 })
```

## Consideraciones de seguridad

1. `keyFile` es la forma minima de autenticacion interna entre miembros.
2. Para produccion endurecida, MongoDB recomienda usar certificados `X.509` para autenticacion interna.
3. Usa contraseñas largas y aleatorias.
4. No publiques los puertos de MongoDB hacia internet.
5. Restringe acceso por firewall y red privada.
6. Rota el `mongo.key` y las credenciales siguiendo una ventana controlada de mantenimiento.

## Limpieza local

Para bajar el laboratorio local:

```bash
docker compose --env-file .env -f node1/docker-compose.yml down
docker compose --env-file .env -f node2/docker-compose.yml down
docker compose --env-file .env -f node3/docker-compose.yml down
```

Para eliminar tambien los datos persistidos del laboratorio local:

```bash
rm -rf node1/data node2/data node3/data
rm -f node1/mongo.key node2/mongo.key node3/mongo.key mongo.key
```

## Nota sobre deploy.sh

`deploy.sh` esta pensado para el escenario local en una sola maquina, porque necesita:

1. Generar y copiar el keyfile localmente.
2. Levantar los tres nodos locales.
3. Usar la localhost exception sobre `node1` para `rs.initiate()` y crear el primer usuario.

Para el escenario distribuido, el README documenta el procedimiento manual seguro usando exactamente los mismos archivos de configuracion.

# Replica Set Manual Sin Docker

Este documento explica como montar manualmente la replicacion de este proyecto sin usar Docker.

La idea es reproducir exactamente la logica del proyecto:

1. Tres nodos MongoDB.
2. Un replica set llamado `rs0`.
3. Un `keyFile` compartido para autenticacion interna.
4. Un nodo 1 con prioridad `2`.
5. Un nodo 2 y un nodo 3 con prioridad `1`.
6. Un usuario administrador en la base `admin`.

## Que replica este proyecto

Segun `deploy.sh`, `.env` y los `docker-compose.yml`, el proyecto hace esto:

1. Usa MongoDB `6.0.14`.
2. Arranca cada `mongod` con `--replSet rs0`.
3. Usa `--keyFile` para que los miembros del replica set se autentiquen entre si.
4. Expone tres nodos con estos valores por defecto:
5. `mongo-node1:27117`
6. `mongo-node2:27118`
7. `mongo-node3:27119`
8. Inicializa el replica set con esta prioridad:
9. nodo 1: `priority: 2`
10. nodo 2: `priority: 1`
11. nodo 3: `priority: 1`
12. Crea el usuario `admin` con rol `root` en `admin`.

Este README hace todo eso sin contenedores.

## Escenarios soportados

Puedes hacerlo de dos formas:

1. Laboratorio local en una sola maquina Linux con 3 procesos `mongod` en puertos distintos.
2. Entorno distribuido en 3 servidores Linux, con un `mongod` por servidor.

La logica del replica set es la misma en ambos casos.

## Requisitos

1. Linux con `systemd`.
2. Acceso `sudo`.
3. Conectividad entre nodos.
4. DNS o `/etc/hosts` bien configurado.
5. `openssl`, `curl` y `gnupg` para instalacion y keyfile.

## Valores equivalentes al proyecto

Si quieres mantener exactamente la configuracion del proyecto, usa estos valores:

```text
Replica set: rs0

Usuario admin: admin
Password admin: change_this_admin_password_now

Nodo 1:
  host: mongo-node1
  puerto: 27117

Nodo 2:
  host: mongo-node2
  puerto: 27118

Nodo 3:
  host: mongo-node3
  puerto: 27119
```

En un entorno distribuido tambien puedes usar `27017` en los tres servidores. Lo importante es que `rs.initiate(...)` use los `host:puerto` reales.

## Paso 1: instalar MongoDB sin Docker

Ejemplo para Ubuntu 22.04 o distribuciones compatibles.

Si usas otra distro o version, cambia el repositorio por el oficial equivalente de MongoDB 6.0.

```bash
sudo apt-get update
sudo apt-get install -y curl gnupg
curl -fsSL https://pgp.mongodb.com/server-6.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
```

Esto instala:

1. `mongod`.
2. `mongosh`.
3. Herramientas administrativas de MongoDB.

Comprueba la instalacion:

```bash
mongod --version
mongosh --version
```

## Paso 2: configurar resolucion de nombres

El replica set debe registrar hostnames estables. Esos nombres deben resolver entre todos los nodos y tambien desde los clientes.

### Opcion A: una sola maquina

Agrega esto a `/etc/hosts`:

```text
127.0.0.1 mongo-node1
127.0.0.1 mongo-node2
127.0.0.1 mongo-node3
```

### Opcion B: tres servidores

Ejemplo si cada servidor tiene una IP privada distinta:

```text
10.10.10.11 mongo-node1
10.10.10.12 mongo-node2
10.10.10.13 mongo-node3
```

Debes poner las tres lineas en las tres maquinas, salvo que ya tengas DNS interno.

## Paso 3: crear el keyfile compartido

El proyecto usa un `keyFile` comun para autenticacion interna entre miembros del replica set. Sin eso, los nodos no deben replicar entre si.

Generalo una sola vez:

```bash
openssl rand -base64 756 > mongo.key
chmod 400 mongo.key
```

### Si estas en una sola maquina

Instalalo en una ruta fija:

```bash
sudo mkdir -p /etc/mongodb-replica
sudo install -o mongodb -g mongodb -m 400 mongo.key /etc/mongodb-replica/mongo.key
```

### Si estas en tres servidores

1. Genera `mongo.key` una sola vez.
2. Copia exactamente el mismo archivo a los tres servidores.
3. En cada servidor, instalalo asi:

```bash
sudo mkdir -p /etc/mongodb-replica
sudo install -o mongodb -g mongodb -m 400 mongo.key /etc/mongodb-replica/mongo.key
```

Todos los nodos deben usar el mismo contenido y permisos `400`.

## Paso 4: preparar directorios de datos y logs

### Opcion A: una sola maquina con 3 nodos

```bash
sudo mkdir -p /var/lib/mongo-rs/node1
sudo mkdir -p /var/lib/mongo-rs/node2
sudo mkdir -p /var/lib/mongo-rs/node3
sudo mkdir -p /var/log/mongo-rs
sudo chown -R mongodb:mongodb /var/lib/mongo-rs /var/log/mongo-rs
```

### Opcion B: tres servidores

En cada servidor crea solo su directorio local:

Servidor 1:

```bash
sudo mkdir -p /var/lib/mongo-rs/node1
sudo mkdir -p /var/log/mongo-rs
sudo chown -R mongodb:mongodb /var/lib/mongo-rs /var/log/mongo-rs
```

Servidor 2:

```bash
sudo mkdir -p /var/lib/mongo-rs/node2
sudo mkdir -p /var/log/mongo-rs
sudo chown -R mongodb:mongodb /var/lib/mongo-rs /var/log/mongo-rs
```

Servidor 3:

```bash
sudo mkdir -p /var/lib/mongo-rs/node3
sudo mkdir -p /var/log/mongo-rs
sudo chown -R mongodb:mongodb /var/lib/mongo-rs /var/log/mongo-rs
```

## Paso 5: crear archivos de configuracion de MongoDB

Sin Docker, el equivalente de los `docker-compose.yml` es crear archivos `.conf` para cada `mongod`.

### Opcion A: una sola maquina con 3 procesos `mongod`

Primero crea la carpeta de configuracion:

```bash
sudo mkdir -p /etc/mongod-rs
```

### `node1.conf`

Guarda este archivo en `/etc/mongod-rs/node1.conf`:

```yaml
storage:
  dbPath: /var/lib/mongo-rs/node1
systemLog:
  destination: file
  path: /var/log/mongo-rs/node1.log
  logAppend: true
net:
  port: 27117
  bindIpAll: true
replication:
  replSetName: rs0
security:
  keyFile: /etc/mongodb-replica/mongo.key
```

### `node2.conf`

Guarda este archivo en `/etc/mongod-rs/node2.conf`:

```yaml
storage:
  dbPath: /var/lib/mongo-rs/node2
systemLog:
  destination: file
  path: /var/log/mongo-rs/node2.log
  logAppend: true
net:
  port: 27118
  bindIpAll: true
replication:
  replSetName: rs0
security:
  keyFile: /etc/mongodb-replica/mongo.key
```

### `node3.conf`

Guarda este archivo en `/etc/mongod-rs/node3.conf`:

```yaml
storage:
  dbPath: /var/lib/mongo-rs/node3
systemLog:
  destination: file
  path: /var/log/mongo-rs/node3.log
  logAppend: true
net:
  port: 27119
  bindIpAll: true
replication:
  replSetName: rs0
security:
  keyFile: /etc/mongodb-replica/mongo.key
```

### Opcion B: tres servidores

En cada servidor crea `/etc/mongod-rs/nodeX.conf` segun corresponda.

Servidor 1, `/etc/mongod-rs/node1.conf`:

```yaml
storage:
  dbPath: /var/lib/mongo-rs/node1
systemLog:
  destination: file
  path: /var/log/mongo-rs/node1.log
  logAppend: true
net:
  port: 27017
  bindIpAll: true
replication:
  replSetName: rs0
security:
  keyFile: /etc/mongodb-replica/mongo.key
```

Servidor 2, `/etc/mongod-rs/node2.conf`:

```yaml
storage:
  dbPath: /var/lib/mongo-rs/node2
systemLog:
  destination: file
  path: /var/log/mongo-rs/node2.log
  logAppend: true
net:
  port: 27017
  bindIpAll: true
replication:
  replSetName: rs0
security:
  keyFile: /etc/mongodb-replica/mongo.key
```

Servidor 3, `/etc/mongod-rs/node3.conf`:

```yaml
storage:
  dbPath: /var/lib/mongo-rs/node3
systemLog:
  destination: file
  path: /var/log/mongo-rs/node3.log
  logAppend: true
net:
  port: 27017
  bindIpAll: true
replication:
  replSetName: rs0
security:
  keyFile: /etc/mongodb-replica/mongo.key
```

## Paso 6: crear servicios `systemd`

Para manejar MongoDB sin Docker, puedes usar un servicio plantilla y arrancar una instancia por nodo.

Guarda este archivo en `/etc/systemd/system/mongod-rs@.service`:

```ini
[Unit]
Description=MongoDB Replica Set Node %i
After=network.target

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod-rs/%i.conf
Restart=always
RestartSec=3
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
```

Recarga `systemd`:

```bash
sudo systemctl daemon-reload
```

## Paso 7: arrancar cada base de datos

### Opcion A: una sola maquina

Levanta las tres instancias:

```bash
sudo systemctl enable --now mongod-rs@node1
sudo systemctl enable --now mongod-rs@node2
sudo systemctl enable --now mongod-rs@node3
```

### Opcion B: tres servidores

Cada servidor arranca solo su nodo:

Servidor 1:

```bash
sudo systemctl enable --now mongod-rs@node1
```

Servidor 2:

```bash
sudo systemctl enable --now mongod-rs@node2
```

Servidor 3:

```bash
sudo systemctl enable --now mongod-rs@node3
```

## Paso 8: verificar que MongoDB este escuchando

### Opcion A: una sola maquina

```bash
mongosh --host 127.0.0.1 --port 27117 --eval 'db.adminCommand({ ping: 1 }).ok'
mongosh --host 127.0.0.1 --port 27118 --eval 'db.adminCommand({ ping: 1 }).ok'
mongosh --host 127.0.0.1 --port 27119 --eval 'db.adminCommand({ ping: 1 }).ok'
```

### Opcion B: tres servidores

En cada servidor prueba su nodo local:

Servidor 1:

```bash
mongosh --host 127.0.0.1 --port 27017 --eval 'db.adminCommand({ ping: 1 }).ok'
```

Servidor 2:

```bash
mongosh --host 127.0.0.1 --port 27017 --eval 'db.adminCommand({ ping: 1 }).ok'
```

Servidor 3:

```bash
mongosh --host 127.0.0.1 --port 27017 --eval 'db.adminCommand({ ping: 1 }).ok'
```

Cada comando debe devolver `1`.

Tambien puedes revisar el servicio:

```bash
systemctl status mongod-rs@node1
systemctl status mongod-rs@node2
systemctl status mongod-rs@node3
```

## Paso 9: iniciar el replica set manualmente

Este es el equivalente directo de la funcion `initiate_replicaset()` del proyecto.

Debes hacerlo desde el nodo 1.

### Opcion A: una sola maquina

```bash
mongosh --host 127.0.0.1 --port 27117
```

Luego ejecuta:

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo-node1:27117", priority: 2 },
    { _id: 1, host: "mongo-node2:27118", priority: 1 },
    { _id: 2, host: "mongo-node3:27119", priority: 1 }
  ]
})
```

### Opcion B: tres servidores

En el servidor 1:

```bash
mongosh --host 127.0.0.1 --port 27017
```

Luego ejecuta:

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

Debes adaptar los `host:puerto` a tu red real.

## Paso 10: esperar a que exista un `primary`

El proyecto espera a que el nodo 1 se vuelva `primary`.

Compruebalo asi:

### Opcion A: una sola maquina

```bash
mongosh --host 127.0.0.1 --port 27117 --eval 'db.hello().isWritablePrimary ? "primary" : "waiting"'
```

### Opcion B: tres servidores

```bash
mongosh --host 127.0.0.1 --port 27017 --eval 'db.hello().isWritablePrimary ? "primary" : "waiting"'
```

Repite hasta ver `primary`.

Tambien puedes revisar el estado completo:

```bash
mongosh --host 127.0.0.1 --port 27117 --eval 'rs.status()'
```

Si estas en 3 servidores, cambia el puerto segun corresponda.

## Paso 11: crear el usuario administrador

Este es el equivalente del paso `ensure_admin_user()` del proyecto.

Hazlo desde el nodo 1 cuando ya sea `primary`.

### Opcion A: una sola maquina

```bash
mongosh --host 127.0.0.1 --port 27117
```

### Opcion B: tres servidores

```bash
mongosh --host 127.0.0.1 --port 27017
```

Dentro de `mongosh`, ejecuta:

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

Sustituye el usuario y password si cambiaste esos valores.

## Paso 12: verificar autenticacion y replica set

Despues de crear el usuario, valida el acceso.

### Opcion A: una sola maquina

```bash
mongosh 'mongodb://admin:change_this_admin_password_now@mongo-node1:27117,mongo-node2:27118,mongo-node3:27119/admin?replicaSet=rs0'
```

### Opcion B: tres servidores

```bash
mongosh 'mongodb://admin:change_this_admin_password_now@mongo-node1:27017,mongo-node2:27017,mongo-node3:27017/admin?replicaSet=rs0'
```

Dentro de `mongosh` prueba:

```javascript
rs.status()
db.adminCommand({ ping: 1 })
```

Tambien puedes validar directo por linea de comando:

```bash
mongosh 'mongodb://admin:change_this_admin_password_now@mongo-node1:27117,mongo-node2:27118,mongo-node3:27119/admin?replicaSet=rs0' --eval 'rs.status().ok'
```

Debe devolver `1`.

## Paso 13: comprobar replicacion real

Para verificar que la replicacion funciona de verdad:

1. Conectate al `primary` autenticado.
2. Crea una base y una coleccion.
3. Inserta un documento.
4. Lee ese documento desde otro nodo.

Ejemplo en el `primary`:

```javascript
use laboratorio
db.prueba.insertOne({ mensaje: 'replicacion ok', fecha: new Date() })
```

Luego conecta a otro nodo con la misma cadena y consulta:

```javascript
use laboratorio
db.prueba.find().pretty()
```

Si el documento aparece, la replicacion ya esta funcionando.

## Firewall recomendado

El proyecto original expone `mongod` con `bind_ip_all`, asi que debes proteger los puertos a nivel de red.

Permite solo:

1. Trafico entre los miembros del replica set.
2. Trafico desde hosts de administracion confiables.
3. Nunca abras MongoDB a internet publica.

## Relacion entre este README y el proyecto

La equivalencia es esta:

1. `docker-compose.yml` arranca `mongod` con `replSet`, `keyFile` y `bind_ip_all`.
2. Aqui eso se reemplaza con archivos `mongod.conf` y servicios `systemd`.
3. `deploy.sh` genera y distribuye `mongo.key`.
4. Aqui eso se hace con `openssl` e instalacion manual del archivo.
5. `deploy.sh` ejecuta `rs.initiate(...)`.
6. Aqui lo haces desde `mongosh` manualmente.
7. `deploy.sh` crea el usuario admin.
8. Aqui haces `db.createUser(...)` de forma manual.

## Resumen rapido

Si quieres la version corta del proceso manual sin Docker:

1. Instala MongoDB 6.0 y `mongosh`.
2. Configura hostnames reales.
3. Genera un `mongo.key` compartido.
4. Crea directorios de datos y logs.
5. Crea un `mongod.conf` por nodo.
6. Arranca cada `mongod` con `systemd`.
7. Verifica `ping` en cada nodo.
8. Ejecuta `rs.initiate(...)` desde el nodo 1.
9. Espera a que haya `primary`.
10. Crea el usuario admin.
11. Conectate con la cadena `mongodb://...?...replicaSet=rs0`.

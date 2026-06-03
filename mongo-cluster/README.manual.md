# Despliegue Manual del Replica Set

Este documento explica como hacer manualmente todo lo que automatiza `deploy.sh`.

El objetivo es:

1. Preparar la configuracion.
2. Generar y distribuir el `keyfile`.
3. Levantar cada nodo de MongoDB por separado.
4. Inicializar el replica set.
5. Esperar a que exista un `primary`.
6. Crear el usuario administrador.
7. Verificar que el cluster quede operativo.

Aplica al proyecto dentro de `mongo-cluster/`.

## Que hace `deploy.sh`

El script automatiza estas acciones:

1. Verifica que exista `.env`.
2. Verifica que todas las variables obligatorias tengan valor.
3. Verifica que existan `docker`, `docker compose` y `openssl`.
4. Genera `mongo.key` si todavia no existe.
5. Copia el mismo `mongo.key` a `node1`, `node2` y `node3` con permisos `400`.
6. Crea `node1/data`, `node2/data` y `node3/data`.
7. Levanta los 3 contenedores con Docker Compose.
8. Espera a que los contenedores esten `healthy`.
9. Espera a que MongoDB responda `ping` en los 3 nodos.
10. Revisa si el replica set ya esta inicializado.
11. Si no lo esta, ejecuta `rs.initiate(...)` desde el nodo 1.
12. Espera a que el nodo 1 sea `primary`.
13. Revisa si el usuario administrador ya existe.
14. Si no existe, lo crea en la base `admin`.

Este README repite esas acciones una por una.

## Requisitos

Necesitas lo siguiente en la maquina donde vas a hacer el despliegue manual local:

1. Docker Engine.
2. `docker compose`.
3. `openssl`.
4. Permisos para ejecutar Docker.
5. La carpeta `mongo-cluster` completa.

## Estructura usada

```text
mongo-cluster/
├── .env
├── deploy.sh
├── README.md
├── README.manual.md
├── node1/
│   └── docker-compose.yml
├── node2/
│   └── docker-compose.yml
└── node3/
    └── docker-compose.yml
```

## Paso 1: preparar el archivo `.env`

El script no puede funcionar si falta `.env` o si alguna variable obligatoria esta vacia.

Si todavia no existe, crea `.env` a partir de `.env.example`.

Ejemplo de contenido:

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

Cada variable se usa asi:

1. `MONGO_IMAGE`: imagen de MongoDB.
2. `MONGO_REPLICA_SET_NAME`: nombre del replica set.
3. `MONGO_ROOT_USERNAME` y `MONGO_ROOT_PASSWORD`: credenciales del administrador que se crea al final.
4. `MONGO_NODE*_HOST`: hostname que se registra en el replica set.
5. `MONGO_NODE*_ADDRESS`: IP que se inyecta en `extra_hosts` dentro de los contenedores.
6. `MONGO_NODE*_PORT`: puerto donde escucha cada nodo.
7. `MONGO_NODE*_NAME`: nombre del contenedor Docker.

## Paso 2: verificar resolucion de nombres

Como el replica set se forma usando los hostnames del `.env`, esos nombres deben resolver correctamente.

Para un despliegue local en una sola maquina, puedes agregar esto a `/etc/hosts`:

```text
127.0.0.1 mongo-node1
127.0.0.1 mongo-node2
127.0.0.1 mongo-node3
```

Esto es importante porque `rs.initiate()` registrara los miembros como:

1. `mongo-node1:27117`
2. `mongo-node2:27118`
3. `mongo-node3:27119`

Si esos nombres no resuelven, clientes y nodos pueden fallar al intentar reconectarse o replicar.

## Paso 3: generar el `keyfile`

MongoDB usa un `keyFile` comun para autenticar la comunicacion interna entre miembros del replica set.

`deploy.sh` hace esto:

```bash
openssl rand -base64 756 > mongo.key
chmod 400 mongo.key
```

Hazlo manualmente desde `mongo-cluster/`:

```bash
openssl rand -base64 756 > mongo.key
chmod 400 mongo.key
```

Que hace este paso:

1. Genera una clave aleatoria compartida.
2. La deja solo legible por el propietario.
3. Esa misma clave debe usarse en los 3 nodos.

Si ya existe `mongo.key`, no necesitas regenerarlo, salvo que quieras reinicializar todo el entorno con una nueva clave.

## Paso 4: copiar el `keyfile` a cada nodo

Los `docker-compose.yml` montan un archivo distinto en cada carpeta:

1. `node1/mongo.key`
2. `node2/mongo.key`
3. `node3/mongo.key`

Por eso el script copia el mismo contenido a las tres rutas. Haz lo mismo manualmente:

```bash
install -m 400 mongo.key node1/mongo.key
install -m 400 mongo.key node2/mongo.key
install -m 400 mongo.key node3/mongo.key
```

Es importante que los tres archivos tengan exactamente el mismo contenido.

## Paso 5: crear directorios de datos

Cada nodo guarda sus datos persistentes en su carpeta `data`:

1. `node1/data`
2. `node2/data`
3. `node3/data`

Crealos manualmente:

```bash
mkdir -p node1/data node2/data node3/data
```

Esto permite que la informacion sobreviva aunque los contenedores se reinicien.

## Paso 6: levantar cada base de datos

Cada archivo `docker-compose.yml` arranca un `mongod` distinto con:

1. `--replSet ${MONGO_REPLICA_SET_NAME}`
2. `--keyFile /tmp/mongo-keyfile`
3. `--bind_ip_all`
4. El puerto de su nodo

Levantalo manualmente desde `mongo-cluster/`:

```bash
docker compose --env-file .env --project-directory node1 -f node1/docker-compose.yml up -d
docker compose --env-file .env --project-directory node2 -f node2/docker-compose.yml up -d
docker compose --env-file .env --project-directory node3 -f node3/docker-compose.yml up -d
```

Que hace cada uno:

1. `node1/docker-compose.yml` crea el contenedor `${MONGO_NODE1_NAME}`.
2. `node2/docker-compose.yml` crea el contenedor `${MONGO_NODE2_NAME}`.
3. `node3/docker-compose.yml` crea el contenedor `${MONGO_NODE3_NAME}`.

En este proyecto se usa `network_mode: host`, asi que cada contenedor escucha directamente en el puerto del host definido en `.env`.

## Paso 7: esperar a que los contenedores esten sanos

El script espera primero a que Docker reporte estado `healthy`.

Puedes revisarlo con:

```bash
docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' mongo-rs-node1
docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' mongo-rs-node2
docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' mongo-rs-node3
```

Si configuraste nombres de contenedor distintos en `.env`, reemplaza `mongo-rs-node1`, `mongo-rs-node2` y `mongo-rs-node3` por los valores reales.

Debes esperar a que los tres muestren `healthy`.

## Paso 8: comprobar que MongoDB responde en cada nodo

Despues del `healthcheck`, el script ejecuta un `ping` contra MongoDB dentro de cada contenedor.

Hazlo asi:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117 --eval 'db.adminCommand({ ping: 1 }).ok'
docker exec -i mongo-rs-node2 mongosh --quiet --port 27118 --eval 'db.adminCommand({ ping: 1 }).ok'
docker exec -i mongo-rs-node3 mongosh --quiet --port 27119 --eval 'db.adminCommand({ ping: 1 }).ok'
```

Cada comando debe devolver:

```text
1
```

Si usas otros puertos o nombres de contenedor, ajusta esos valores segun `.env`.

## Paso 9: comprobar si el replica set ya esta inicializado

Antes de ejecutar `rs.initiate(...)`, el script intenta detectar si el replica set ya existe.

Puedes revisar eso desde el nodo 1 con este comando sin autenticacion:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117 --eval 'try { rs.status().ok } catch (error) { print("not_initiated") }'
```

Resultados esperados:

1. `not_initiated`: todavia no se ha creado el replica set.
2. `1`: el replica set ya esta inicializado.

Si obtienes `1`, no debes volver a correr `rs.initiate(...)`.

## Paso 10: inicializar el replica set manualmente

Si el paso anterior devolvio `not_initiated`, inicializa el replica set desde el nodo 1:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117
```

Dentro de `mongosh`, ejecuta:

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

Debes adaptar estos valores a tu `.env`:

1. `_id` debe ser `MONGO_REPLICA_SET_NAME`.
2. Cada `host` debe coincidir con `MONGO_NODE*_HOST:MONGO_NODE*_PORT`.
3. El nodo 1 usa prioridad `2`.
4. Los nodos 2 y 3 usan prioridad `1`.

Por que se hace asi:

1. MongoDB necesita conocer todos los miembros desde el inicio.
2. Los `host:port` registrados son los que usaran los clientes y la replicacion interna.
3. La prioridad mas alta en el nodo 1 hace mas probable que sea elegido `primary`.

## Paso 11: esperar a que el nodo 1 se convierta en `primary`

Despues de `rs.initiate(...)`, la eleccion del `primary` puede tardar unos segundos.

El script verifica esto con `db.hello().isWritablePrimary`.

Haz la comprobacion manualmente:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117 --eval 'db.hello().isWritablePrimary ? "primary" : "waiting"'
```

Debes repetirlo hasta obtener:

```text
primary
```

Si prefieres una revision mas completa:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117 --eval 'rs.status()'
```

## Paso 12: comprobar si el usuario administrador ya existe

El script intenta autenticarse y consultar si el usuario existe. Como en un despliegue nuevo todavia no existe, este paso normalmente fallara al principio, y eso es esperado.

La comprobacion util manual es esta, una vez que ya tengas credenciales creadas:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117 --username admin --password 'change_this_admin_password_now' --authenticationDatabase admin --eval 'db.getSiblingDB("admin").getUser("admin") ? "yes" : "no"'
```

Si todavia no existe el usuario, pasa al paso siguiente.

## Paso 13: crear el usuario administrador

Una vez que el nodo 1 ya es `primary`, crea el usuario administrador usando la localhost exception dentro del mismo contenedor:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117
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

Sustituye:

1. `'admin'` por `MONGO_ROOT_USERNAME`.
2. `'change_this_admin_password_now'` por `MONGO_ROOT_PASSWORD`.

Por que este paso funciona sin autenticacion previa:

1. El nodo aun no tiene usuarios administrativos creados.
2. MongoDB permite esta primera creacion desde localhost.
3. El script aprovecha exactamente ese comportamiento.

## Paso 14: verificar que el usuario funciona

Despues de crear el usuario, validalo autenticando contra `admin`:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117 --username admin --password 'change_this_admin_password_now' --authenticationDatabase admin --eval 'db.getSiblingDB("admin").getUser("admin") ? "yes" : "no"'
```

El resultado esperado es:

```text
yes
```

Tambien puedes probar el estado del replica set autenticado:

```bash
docker exec -i mongo-rs-node1 mongosh --quiet --port 27117 --username admin --password 'change_this_admin_password_now' --authenticationDatabase admin --eval 'rs.status().ok'
```

El resultado esperado es:

```text
1
```

## Paso 15: resumen del cluster listo

Si todo salio bien, tu cluster queda equivalente a lo que reporta `deploy.sh`:

1. Replica set: `rs0`
2. Nodo 1: `mongo-node1:27117`
3. Nodo 2: `mongo-node2:27118`
4. Nodo 3: `mongo-node3:27119`

Con los valores por defecto, la cadena de conexion seria:

```text
mongodb://admin:change_this_admin_password_now@mongo-node1:27117,mongo-node2:27118,mongo-node3:27119/admin?replicaSet=rs0
```

## Comandos de verificacion rapida

### Ver los contenedores

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

### Ver logs de un nodo

```bash
docker logs mongo-rs-node1
```

### Entrar autenticado al replica set

```bash
mongosh 'mongodb://admin:change_this_admin_password_now@mongo-node1:27117,mongo-node2:27118,mongo-node3:27119/admin?replicaSet=rs0'
```

### Revisar estado dentro de MongoDB

```javascript
rs.status()
db.adminCommand({ ping: 1 })
```

## Equivalencia directa con `deploy.sh`

Si quieres mapear cada funcion del script con una accion manual:

1. `ensure_keyfile`: pasos 3 y 4.
2. `start_nodes`: pasos 5 y 6.
3. `wait_for_all_nodes`: pasos 7 y 8.
4. `initiate_replicaset`: pasos 9 y 10.
5. `wait_for_primary`: paso 11.
6. `ensure_admin_user`: pasos 12, 13 y 14.
7. `print_summary`: paso 15.

## Si quieres hacerlo en 3 servidores distintos

La logica manual es la misma, con estas diferencias:

1. Cada servidor levanta solo su propio `docker-compose.yml`.
2. Los tres servidores deben compartir el mismo `.env`.
3. Los tres servidores deben compartir el mismo `mongo.key`.
4. En `MONGO_NODE*_ADDRESS` debes usar las IPs reales de cada maquina.
5. `rs.initiate(...)` debe usar los hostnames y puertos reales accesibles entre servidores.

Ejemplo de arranque:

Servidor 1:

```bash
docker compose --env-file .env --project-directory node1 -f node1/docker-compose.yml up -d
```

Servidor 2:

```bash
docker compose --env-file .env --project-directory node2 -f node2/docker-compose.yml up -d
```

Servidor 3:

```bash
docker compose --env-file .env --project-directory node3 -f node3/docker-compose.yml up -d
```

Luego haces `rs.initiate(...)` y `createUser(...)` desde el servidor que aloja `node1`.

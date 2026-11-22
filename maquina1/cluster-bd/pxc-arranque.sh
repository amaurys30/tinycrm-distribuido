#!/bin/bash
# =====================================================================
# Envoltura del entrypoint oficial de Percona XtraDB Cluster.
# Decide si este nodo debe CREAR el cluster (bootstrap) o UNIRSE a el:
#  - Primera vez: solo el nodo con PXC_BOOTSTRAP=1 (pxc1) lo crea.
#  - Reinicios:   se une a los demas, salvo que haya sido el ultimo nodo
#                 en apagarse (safe_to_bootstrap: 1 en grastate.dat).
# Esto evita el "split-brain" cuando pxc1 se reinicia con el cluster vivo.
# =====================================================================
DATADIR=/var/lib/mysql
GRASTATE="$DATADIR/grastate.dat"

# ¿Responde algun otro nodo del cluster (puerto Galera 4567)? ~30 s maximo
otros_nodos_vivos() {
    local yo
    yo=$(hostname -I | awk '{print $1}')
    for intento in 1 2 3 4 5; do
        for p in ${PXC_PEERS//,/ }; do
            [ "$p" = "$yo" ] && continue
            if timeout 2 bash -c "</dev/tcp/$p/4567" 2>/dev/null; then
                echo ">> [pxc] El nodo $p esta vivo"
                return 0
            fi
        done
        sleep 2
    done
    return 1
}

if [ ! -d "$DATADIR/mysql" ]; then
    if [ "$PXC_BOOTSTRAP" = "1" ]; then
        echo ">> [pxc] Nodo nuevo: CREANDO el cluster (bootstrap)"
        unset CLUSTER_JOIN
    else
        echo ">> [pxc] Nodo nuevo: UNIENDOSE al cluster ($PXC_PEERS) via SST"
        export CLUSTER_JOIN="$PXC_PEERS"
    fi
elif grep -q '^safe_to_bootstrap: *1' "$GRASTATE" 2>/dev/null; then
    echo ">> [pxc] Fue el ultimo nodo en apagarse: RE-CREANDO el cluster"
    unset CLUSTER_JOIN
elif [ "$PXC_BOOTSTRAP" = "1" ] && ! otros_nodos_vivos; then
    # Nodo de arranque designado (pxc1) y NINGUN otro nodo encendido:
    # nadie mas puede crear el cluster, asi que lo crea este nodo.
    # (Equivale a "reparar-cluster-bd": supone que pxc1 tiene los datos
    #  mas recientes, que es lo normal si se apaga de ultimo.)
    echo ">> [pxc] AVISO: safe_to_bootstrap=0 pero ningun otro nodo responde."
    echo ">> [pxc] Este es el nodo de arranque: se marca safe_to_bootstrap=1 y se RE-CREA el cluster"
    sed -i 's/^safe_to_bootstrap: *0/safe_to_bootstrap: 1/' "$GRASTATE"
    unset CLUSTER_JOIN
else
    echo ">> [pxc] Nodo existente: UNIENDOSE al cluster ($PXC_PEERS) via IST/SST"
    export CLUSTER_JOIN="$PXC_PEERS"
fi

# ---------------------------------------------------------------------
# Configuracion del nodo. Se ESCRIBE dentro del contenedor (no se monta
# desde Windows: alli los archivos aparecen con permisos 777 y MySQL los
# ignora). Debe estar en un .cnf y no solo en la linea de comandos,
# porque el script de copia entre nodos (SST, wsrep_sst_xtrabackup-v2)
# solo lee los archivos .cnf: si no ve pxc-encrypt-cluster-traffic=OFF,
# asume cifrado y falla con "Could not find a CA file".
# ---------------------------------------------------------------------
cat > /etc/percona-xtradb-cluster.conf.d/zz-tinycrm.cnf <<'CNF'
[mysqld]
# Los nodos no comparten certificados: replicacion sin TLS (red interna aislada)
pxc-encrypt-cluster-traffic=OFF
pxc_strict_mode=PERMISSIVE
innodb_buffer_pool_size=256M
max_connections=300
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
CNF
echo ">> [pxc] Configuracion escrita en /etc/percona-xtradb-cluster.conf.d/zz-tinycrm.cnf"

# Si el nodo va a CREAR el cluster, la direccion debe quedar vacia (gcomm://).
# Importante en reinicios (docker stop/start): el contenedor conserva el
# node.cnf de la vez anterior, que puede tener la lista de pares de cuando
# este nodo se UNIO; con esa lista esperaria para siempre a nodos apagados.
if [ -z "$CLUSTER_JOIN" ]; then
    sed -i 's|^wsrep_cluster_address=.*|wsrep_cluster_address=gcomm://|' /etc/mysql/node.cnf
fi

exec /entrypoint.sh "$@"

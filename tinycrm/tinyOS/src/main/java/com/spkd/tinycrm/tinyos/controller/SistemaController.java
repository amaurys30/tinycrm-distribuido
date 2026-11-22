package com.spkd.tinycrm.tinyos.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.net.InetAddress;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * [SD] Endpoint de diagnostico para la sustentacion: muestra que cliente,
 * que instancia del cluster y que nodo del cluster de BD atendieron la peticion.
 */
@RestController
@RequestMapping("/api/sistema")
public class SistemaController {

    @Value("${app.tenant.id}") private String tenant;
    @Value("${app.tenant.nombre}") private String tenantNombre;
    @Value("${app.instancia}") private String instancia;

    private final DataSource dataSource;

    public SistemaController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @GetMapping("/info")
    public Map<String, Object> info() {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("tenant", tenant);
        r.put("cliente", tenantNombre);
        r.put("instancia", instancia);
        try {
            r.put("hostname", InetAddress.getLocalHost().getHostName());
        } catch (Exception e) {
            r.put("hostname", "desconocido");
        }
        try (Connection c = dataSource.getConnection();
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT @@hostname, DATABASE()")) {
            if (rs.next()) {
                r.put("nodoBD", rs.getString(1));
                r.put("baseDeDatos", rs.getString(2));
            }
        } catch (Exception e) {
            r.put("nodoBD", "error: " + e.getMessage());
        }
        return r;
    }
}

package com.spkd.tinycrm.tinyos.eventos;

import com.spkd.tinycrm.tinyos.entity.User;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** [SD] Construye eventos con el tenant e instancia de este contenedor. */
@Component
public class UsuarioEventoFactory {

    @Value("${app.tenant.id}")
    private String tenant;

    @Value("${app.instancia}")
    private String instancia;

    public UsuarioEvento desde(String tipo, User u) {
        return new UsuarioEvento(tipo, tenant, u.getId(), u.getUsername(), u.getEmail(),
                u.getFirstName(), u.getLastName(),
                u.getRole() != null ? u.getRole().name() : null,
                u.isActive(), instancia);
    }
}

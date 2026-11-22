package com.spkd.tinycrm.tinyos.eventos;

import java.time.Instant;

/**
 * [SD] Evento de dominio que se publica en el broker cuando se crea o
 * elimina un usuario en TinyCRM. El "Consumer" lo usa para mantener el
 * registro central de usuarios (BD "Usuarios") que consulta el Middleware.
 */
public class UsuarioEvento {

    public static final String CREADO = "USUARIO_CREADO";
    public static final String ELIMINADO = "USUARIO_ELIMINADO";

    private String tipo;
    private String tenant;
    private Long usuarioId;
    private String username;
    private String email;
    private String nombre;
    private String apellido;
    private String rol;
    private boolean activo;
    private String instancia;
    private String fecha = Instant.now().toString();

    public UsuarioEvento() { }

    public UsuarioEvento(String tipo, String tenant, Long usuarioId, String username, String email,
                         String nombre, String apellido, String rol, boolean activo, String instancia) {
        this.tipo = tipo;
        this.tenant = tenant;
        this.usuarioId = usuarioId;
        this.username = username;
        this.email = email;
        this.nombre = nombre;
        this.apellido = apellido;
        this.rol = rol;
        this.activo = activo;
        this.instancia = instancia;
    }

    public String getTipo() { return tipo; }
    public String getTenant() { return tenant; }
    public Long getUsuarioId() { return usuarioId; }
    public String getUsername() { return username; }
    public String getEmail() { return email; }
    public String getNombre() { return nombre; }
    public String getApellido() { return apellido; }
    public String getRol() { return rol; }
    public boolean isActivo() { return activo; }
    public String getInstancia() { return instancia; }
    public String getFecha() { return fecha; }

    public void setTipo(String tipo) { this.tipo = tipo; }
    public void setTenant(String tenant) { this.tenant = tenant; }
    public void setUsuarioId(Long usuarioId) { this.usuarioId = usuarioId; }
    public void setUsername(String username) { this.username = username; }
    public void setEmail(String email) { this.email = email; }
    public void setNombre(String nombre) { this.nombre = nombre; }
    public void setApellido(String apellido) { this.apellido = apellido; }
    public void setRol(String rol) { this.rol = rol; }
    public void setActivo(boolean activo) { this.activo = activo; }
    public void setInstancia(String instancia) { this.instancia = instancia; }
    public void setFecha(String fecha) { this.fecha = fecha; }

    /** routing key: usuario.creado.A / usuario.eliminado.B */
    public String routingKey() {
        String accion = ELIMINADO.equals(tipo) ? "eliminado" : "creado";
        return "usuario." + accion + "." + tenant;
    }
}

package com.spkd.tinycrm.tinyos.eventos;

import com.spkd.tinycrm.tinyos.entity.User;
import com.spkd.tinycrm.tinyos.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * [SD] Reconciliacion: al arrancar (y cada N minutos) la instancia vuelve a
 * publicar USUARIO_CREADO para todos sus usuarios. El Consumer hace UPSERT,
 * asi que es idempotente. Cubre el caso en que el broker estuvo caido cuando
 * se creo un usuario (tolerancia a fallos de la mensajeria).
 */
@Component
public class ResincronizacionUsuarios {

    private static final Logger log = LoggerFactory.getLogger(ResincronizacionUsuarios.class);

    private final UserRepository userRepository;
    private final UsuarioEventoFactory factory;
    private final UsuarioEventoPublisher publisher;
    private final boolean habilitada;

    public ResincronizacionUsuarios(UserRepository userRepository,
                                    UsuarioEventoFactory factory,
                                    UsuarioEventoPublisher publisher,
                                    @Value("${app.eventos.resincronizar:true}") boolean habilitada) {
        this.userRepository = userRepository;
        this.factory = factory;
        this.publisher = publisher;
        this.habilitada = habilitada;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void alIniciar() {
        resincronizar("arranque");
    }

    @Scheduled(initialDelayString = "${app.eventos.resincronizar-cada-ms:600000}",
               fixedDelayString = "${app.eventos.resincronizar-cada-ms:600000}")
    public void periodica() {
        resincronizar("periodica");
    }

    private void resincronizar(String motivo) {
        if (!habilitada) {
            return;
        }
        try {
            List<User> usuarios = userRepository.findAll();
            for (User u : usuarios) {
                publisher.publicar(factory.desde(UsuarioEvento.CREADO, u));
            }
            log.info("[EVENTO] Resincronizacion ({}) de {} usuarios", motivo, usuarios.size());
        } catch (Exception e) {
            log.warn("[EVENTO] Resincronizacion ({}) fallida: {}", motivo, e.getMessage());
        }
    }
}

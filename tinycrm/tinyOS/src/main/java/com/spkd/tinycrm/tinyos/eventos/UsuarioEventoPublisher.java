package com.spkd.tinycrm.tinyos.eventos;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * [SD] Publica el evento en RabbitMQ SOLO despues de que la transaccion
 * que creo/elimino el usuario hizo COMMIT en el cluster de BD.
 * Asi nunca se anuncia un usuario que no quedo guardado.
 */
@Component
public class UsuarioEventoPublisher {

    private static final Logger log = LoggerFactory.getLogger(UsuarioEventoPublisher.class);

    private final RabbitTemplate rabbitTemplate;
    private final String exchange;

    public UsuarioEventoPublisher(RabbitTemplate rabbitTemplate,
                                  @Value("${app.eventos.exchange}") String exchange) {
        this.rabbitTemplate = rabbitTemplate;
        this.exchange = exchange;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
    public void publicar(UsuarioEvento evento) {
        try {
            rabbitTemplate.convertAndSend(exchange, evento.routingKey(), evento);
            log.info("[EVENTO] Publicado {} usuario={} tenant={} instancia={}",
                    evento.getTipo(), evento.getUsername(), evento.getTenant(), evento.getInstancia());
        } catch (Exception e) {
            log.error("[EVENTO] No se pudo publicar {} para {}: {}",
                    evento.getTipo(), evento.getUsername(), e.getMessage());
        }
    }
}

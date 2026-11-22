package com.spkd.tinycrm.tinyos.eventos;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * [SD] Topologia del broker. Exchange tipo topic "tinycrm.usuarios" y una
 * cola durable "usuarios.sincronizacion" ligada a "usuario.#".
 * El Consumer declara exactamente lo mismo (declaracion idempotente), asi
 * los eventos no se pierden aunque el Consumer arranque despues.
 */
@Configuration
public class RabbitConfig {

    @Bean
    public TopicExchange usuariosExchange(@Value("${app.eventos.exchange}") String nombre) {
        return new TopicExchange(nombre, true, false);
    }

    @Bean
    public Queue colaSincronizacion(@Value("${app.eventos.cola}") String nombre) {
        return new Queue(nombre, true);
    }

    @Bean
    public Binding bindingUsuarios(Queue colaSincronizacion, TopicExchange usuariosExchange) {
        return BindingBuilder.bind(colaSincronizacion).to(usuariosExchange).with("usuario.#");
    }

    @Bean
    public MessageConverter jsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}

package com.spkd.tinycrm.tinyos.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import org.springframework.web.servlet.resource.PathResourceResolver;

import java.io.IOException;

@Configuration
public class WebConfig implements WebMvcConfigurer {

    // [SD] Carpeta con el build de Vue dentro del contenedor
    @Value("${app.frontend.dir}")
    private String frontendDir;

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        // [SD] Todo se sirve por el mismo origen (www.tiny.com), CORS solo para desarrollo local
        registry.addMapping("/**")
                .allowedOrigins("http://localhost:3000", "http://localhost:8080", "http://www.tiny.com")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH")
                .allowedHeaders("*")
                .allowCredentials(true)
                .maxAge(3600);
    }

    /**
     * [SD] Cada instancia de TinyCRM sirve su propio frontend (Vue) y su API.
     * Las rutas del SPA (/dashboard, /tickets, ...) devuelven index.html.
     */
    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/**")
                .addResourceLocations(frontendDir)
                .resourceChain(true)
                .addResolver(new PathResourceResolver() {
                    @Override
                    protected Resource getResource(String resourcePath, Resource location) throws IOException {
                        Resource solicitado = location.createRelative(resourcePath);
                        if (solicitado.exists() && solicitado.isReadable() && checkResource(solicitado, location)) {
                            return solicitado;
                        }
                        if (resourcePath.startsWith("api/") || resourcePath.startsWith("actuator")) {
                            return null;
                        }
                        Resource index = location.createRelative("index.html");
                        return index.exists() ? index : null;
                    }
                });
    }
}

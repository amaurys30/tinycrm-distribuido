# =====================================================================
# Imagen unica de TinyCRM para el "Cluster Servidor Aplicacion":
# cada instancia sirve el frontend (Vue) y la API (Spring Boot).
# =====================================================================

# ---- 1) Build del frontend Vue ----
FROM node:18-alpine AS frontend
WORKDIR /fe
COPY frontend/package*.json ./
RUN npm ci --silent
COPY frontend/ ./
RUN npm run build

# ---- 2) Build del backend Spring Boot ----
FROM gradle:8.5-jdk17-alpine AS backend
WORKDIR /be
COPY tinyOS/ ./
RUN gradle bootJar --no-daemon -x test

# ---- 3) Imagen final ----
FROM eclipse-temurin:17-jre-alpine
RUN apk add --no-cache curl \
 && addgroup -g 1001 -S spring && adduser -S spring -u 1001 -G spring
WORKDIR /app
COPY --from=backend /be/build/libs/*.jar /app/app.jar
COPY --from=frontend /fe/dist /app/static
RUN chown -R spring:spring /app
USER spring
EXPOSE 8080
ENV JAVA_OPTS="-Xms128m -Xmx384m -XX:+UseContainerSupport"
HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=5 \
  CMD curl -fs http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]

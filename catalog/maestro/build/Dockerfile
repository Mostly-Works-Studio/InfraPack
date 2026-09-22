# Netflix Maestro has no published image, so InfraPack builds maestro-server
# from source on first start (Java 21 + Gradle; several minutes, ~2 GB).
# Pin a commit with MAESTRO_REF for reproducible builds.
FROM eclipse-temurin:21-jdk AS build
ARG MAESTRO_REF=main
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --depth 1 --branch "$MAESTRO_REF" https://github.com/Netflix/maestro.git . \
 && ./gradlew --no-daemon -q :maestro-server:bootJar -x test \
 && cp maestro-server/build/libs/maestro-server*.jar /maestro-server.jar

FROM eclipse-temurin:21-jre
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /maestro-server.jar /app/maestro-server.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/maestro-server.jar"]

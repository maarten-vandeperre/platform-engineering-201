FROM docker.io/library/maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
COPY .mvn .mvn
RUN mvn -B -ntp -DskipTests org.apache.maven.plugins:maven-dependency-plugin:3.6.1:go-offline || true
COPY src ./src
RUN mvn -B -ntp -DskipTests package

FROM docker.io/library/eclipse-temurin:17-jre
WORKDIR /deployments
COPY --from=build /build/target/quarkus-app/lib/ ./lib/
COPY --from=build /build/target/quarkus-app/*.jar ./
COPY --from=build /build/target/quarkus-app/app/ ./app/
COPY --from=build /build/target/quarkus-app/quarkus/ ./quarkus/
EXPOSE 8080
ENV JAVA_OPTS="-Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
ENTRYPOINT ["java", "-jar", "/deployments/quarkus-run.jar"]

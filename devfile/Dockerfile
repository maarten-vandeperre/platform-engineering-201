# Platform Engineering 201 — Dev Spaces workspace (Java 25 + workshop CLI tools)
FROM registry.access.redhat.com/ubi9/openjdk-25:latest

USER 0

RUN dnf install -y \
      gettext \
      jq \
      git \
      python3 \
      perl \
      openssl \
      curl \
      tar \
      gzip \
      which \
      procps-ng \
      findutils \
    && dnf clean all

# Node.js 22 LTS (>=22.12; required by yargs@18 and AAP Management plugin build)
RUN curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - \
    && dnf install -y nodejs \
    && dnf clean all \
    && corepack enable \
    && corepack prepare yarn@1.22.22 --activate

# OpenShift CLI
RUN curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz" \
    | tar -xz -C /usr/local/bin oc kubectl \
    && chmod +x /usr/local/bin/oc /usr/local/bin/kubectl

# Helm 3
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | HELM_INSTALL_DIR=/usr/local/bin bash

# GitHub CLI (optional — create-github-oauth-app.sh)
RUN dnf install -y https://github.com/cli/cli/releases/download/v2.62.0/gh_2.62.0_linux_amd64.rpm \
    && dnf clean all

ENV JAVA_HOME=/usr/lib/jvm/java-25 \
    PATH=/usr/local/bin:/usr/lib/jvm/java-25/bin:${PATH} \
    MAVEN_OPTS="-Dmaven.repo.local=/home/jboss/.m2/repository"

RUN java -version 2>&1 | grep -q 'version "25"' \
    && node --version \
    && node -e 'const [maj,min]=process.versions.node.split(".").map(Number); const ok=(maj===20&&min>=19)||(maj===22&&min>=12)||maj>=23; if(!ok){console.error("Node.js "+process.versions.node+" is too old; need ^20.19.0 || ^22.12.0 || >=23"); process.exit(1)}' \
    && npm --version \
    && yarn --version \
    && oc version --client \
    && helm version --short

WORKDIR /projects
USER 185

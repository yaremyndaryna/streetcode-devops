FROM jenkins/jenkins:lts-jdk17
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends ansible openssh-client curl git \
 && rm -rf /var/lib/apt/lists/*
COPY plugins.txt /tmp/plugins.txt
RUN jenkins-plugin-cli --plugin-file /tmp/plugins.txt
COPY jenkins.yaml /casc/jenkins.yaml
ENV CASC_JENKINS_CONFIG=/casc/jenkins.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
I have a running oc cli, and the project to work in is rh-ee-mvandepe-dev, 
but this should be configurable, so that it is easy to be reused by someone else.

I have two folders: scripts, where you can put shell scripts (only if needed, if it cannot be done through gitops), 
a manifests/gitops folder, where the main work should be done.
These file will be applied by oc apply, but some reference should be there to how it should be done when you have argocd at your disposal.

Everything should be documented step by step for a workshop about developer hub on openshift, 
and all manifests and scripts should be explained. You can chose if this is in a single or multiple markdown files.

create a setup of keycloak with an admin user (user: admin, pwd: r3dh@t) and a user (user: user, pwd: r3dh@t)

validate the apps folder, in which you should have a java - quarkus - postgres - react js application which can do CRUD on people objects 
(first name, last name, age). enable github actions to build an artifact and push it to the github container registry. it should be 
linked to keycloak and the user should have the permissions to do CRUD on the people APIs

create a workshop that installs developer hub on openshift and configures it to show the app deployment, app github actions, 
a software template to get started with such an application. you can use this git repository.

Install Developer Hub on the OpenShift cluster and document how to link this application

Don't stop before this works on openshift. you can validate via CURL and oc commands.

